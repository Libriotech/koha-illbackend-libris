#!/usr/bin/perl

use Modern::Perl;
use Data::Dumper;
use utf8;
binmode STDOUT, ":utf8";
$| = 1; # Don't buffer output

use Koha::Illrequests;
use Koha::Illbackends::Libris::Base;
use C4::Context;

my $dbh = C4::Context->dbh;
my $ill_config = C4::Context->config('interlibrary_loans');
my $sg = Koha::Illbackends::Libris::Base::status_graph();

my $anon = C4::Context->preference( 'AnonymousPatron' );
die "You need to set the AnonymousPatron syspref\n" unless $anon;
say "Anonymous patron: $anon";

# Fields that should be anonymized
my @anon_fields = qw(
    end_user_library_card
    end_user_address
    end_user_approved_by
    end_user_city
    end_user_email
    end_user_first_name
    end_user_institution
    end_user_institution_delivery
    end_user_institution_phone
    end_user_last_name
    end_user_library_card
    end_user_mobile
    end_user_phone
    end_user_user_id
    end_user_zip_code
    enduser_id
    libris_enduser_request_id
    user
    user_id
);

# Status pairs
my %statuses = (
    'IN_ANK' => 'IN_UTL',
    'IN_UTL' => 'IN_RET',
);

# Loop over old statuses
STATUS: foreach my $old_status ( keys %statuses ) {

    my $new_status = $statuses{ $old_status };
    my $old_status_name = $sg->{ $old_status }->{ 'name' };
    my $new_status_name = $sg->{ $new_status }->{ 'name' };

    my $old_requests = Koha::Illrequests->search({ status => $old_status });
    REQUEST: while ( my $req = $old_requests->next ) {

        my $borrowernumber = $req->borrowernumber;
        my $biblionumber   = $req->biblio_id;

        # Check if the item is still on loan. This should catch both loans that have been
        # returned but not yet anonymized, as well as loans that have been returned and
        # immediately anonymized
        my $on_loan = $dbh->selectrow_hashref( 'SELECT issue_id FROM issues WHERE borrowernumber = ? AND itemnumber IN ( SELECT itemnumber FROM items WHERE biblionumber = ? )', undef, $borrowernumber, $biblionumber );
        say Dumper $on_loan;
        my $updated = '';
        if ( ( $old_status eq 'IN_ANK' && $on_loan ) || ( $old_status eq 'IN_UTL' && !$on_loan ) ) {
            # Do the actual update
            $req->status( $new_status );
            $req->store;
            $updated = $new_status;
            # Add a comment
            my $comment = Koha::Illcomment->new({
                illrequest_id  => $req->illrequest_id,
                borrowernumber => $ill_config->{ 'libris_borrowernumber' },
                comment        => "Status ändrad från $old_status_name till $new_status_name.",
            });
            $comment->store();
            # Anonymize and clean up if this was a loan that was just returned
            if ( $req->status eq 'IN_RET' && !$on_loan ) {
                say "Going to anonymize and clean up";
                # 1. We do not anonymize the issue, since it is already returned and can be
                # anonymized by other features in Koha
                # 2. Anonymize the illrequest (replace borrowernumber with AnonymousPatron)
                $req->borrowernumber( $anon );
                $req->store;
                # 3. Anonymize the data from Libris (illrequestattributes)
                foreach my $field ( @anon_fields ) {
                    $req->illrequestattributes->find({ 'type' => $field })->update({ 'value' => '' });
                }
                # 4. Delete the item (move to deleteditems)
                # 5. Delete the record (move to deleted records)
                # The last two deletes are done in Koha::Illbackends::Libris::Base::close()
            }
        }
        say "illrequest_id=" . $req->illrequest_id . " borrowernumber=$borrowernumber biblionumber=$biblionumber new_status=$updated";

    }

}
