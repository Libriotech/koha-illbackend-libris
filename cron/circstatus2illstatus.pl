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

my %statuses = (
    'IN_ANK' => 'IN_UTL',
    'IN_UTL' => 'IN_RET',
);

# Status pairs
foreach my $old_status ( keys %statuses ) {

    my $new_status = $statuses{ $old_status };
    my $old_status_name = $sg->{ $old_status }->{ 'name' };
    my $new_status_name = $sg->{ $new_status }->{ 'name' };

    my $old_requests = Koha::Illrequests->search({ status => $old_status });
    while ( my $req = $old_requests->next ) {

        my $borrowernumber = $req->borrowernumber;
        my $biblionumber   = $req->biblio_id;

        my $on_loan = $dbh->selectrow_hashref( 'SELECT issue_id FROM issues WHERE borrowernumber = ? AND itemnumber IN ( SELECT itemnumber FROM items WHERE biblionumber = ? )', undef, $borrowernumber, $biblionumber );
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
        }
        say $req->illrequest_id . " $borrowernumber $biblionumber $updated";

    }

}
