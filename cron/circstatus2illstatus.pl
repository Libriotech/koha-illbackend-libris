#!/usr/bin/perl

use Modern::Perl;
use YAML::Syck;
use Data::Dumper;
use utf8;
binmode STDOUT, ":utf8";
$| = 1; # Don't buffer output

use Koha::Illrequests;
use Koha::Illbackends::Libris::Base;
use C4::Context;

my $dbh = C4::Context->dbh;

# Get the path to, and read in, the Libris ILL config file
my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
my $ill_config = LoadFile( $ill_config_file );

my $sg = Koha::Illbackends::Libris::Base::status_graph();

my $anon = C4::Context->preference( 'AnonymousPatron' );
die "You need to set the AnonymousPatron syspref\n" unless $anon;
say "Anonymous patron: $anon";

# Status pairs
my %statuses = (
    'IN_ANK' => 'IN_UTL',
    'IN_UTL' => 'IN_RET',
);

# Loop over old statuses
STATUS: foreach my $old_status ( keys %statuses ) {

    say "Looking at $old_status";

    my $new_status = $statuses{ $old_status };
    my $old_status_name = $sg->{ $old_status }->{ 'name' };
    my $new_status_name = $sg->{ $new_status }->{ 'name' };

    my $old_requests = Koha::Illrequests->search({ status => $old_status });
    REQUEST: while ( my $req = $old_requests->next ) {

        say "Looking at request";

        my $borrowernumber = $req->borrowernumber;
        say "borrowernumber = $borrowernumber";
        my $biblionumber   = $req->biblio_id;
        say "biblionumber = $biblionumber";

        # Check if the item is still on loan. This should catch both loans that have been
        # returned but not yet anonymized, as well as loans that have been returned and
        # immediately anonymized
        my $on_loan = $dbh->selectrow_hashref( 'SELECT issue_id FROM issues WHERE borrowernumber = ? AND itemnumber IN ( SELECT itemnumber FROM items WHERE biblionumber = ? )', undef, $borrowernumber, $biblionumber );
        say Dumper $on_loan;
        my $updated = '';
        if ( ( $old_status eq 'IN_ANK' && $on_loan ) || ( $old_status eq 'IN_UTL' && !$on_loan ) ) {
            say "Going to update status";
            # Do the actual update
            $req->status( $new_status );
            say "FROM $old_status to $new_status";
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
                my $params = {
                    'other'   => { 'stage' => 'commit' },
                    'request' => $req,
                };
                Koha::Illbackends::Libris::Base::close( $params );
            }
        } else {
            say "NOT going to update status";
        }
        say "illrequest_id=" . $req->illrequest_id . " borrowernumber=$borrowernumber biblionumber=$biblionumber new_status=$updated";

    }

}
