#!/usr/bin/perl

use LWP;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON qw( decode_json );
use Scalar::Util qw( reftype );
use Getopt::Long;
use Data::Dumper;
use Template;
use DateTime;
use Pod::Usage;
use Modern::Perl;
binmode STDOUT, ":utf8";

use C4::Context;
use Koha::ILL::Requests;
use Koha::ILL::Request::Config;

my $ill_config = C4::Context->config('interlibrary_loans');
my $dbh = C4::Context->dbh;

my $orderid = "5675844";
die unless $orderid;

my $orig_data = get_data( "illrequests/__sigil__/$orderid" );
say Dumper $orig_data;

# FIXME Pick out the timestamp
my $timestamp = $orig_data->{ 'ill_requests' }->[0]->{ 'last_modified' };
say Dumper $timestamp;
die unless $timestamp;

## Make the call back to Libris, to change the status

# Create a user agent object
my $ua = LWP::UserAgent->new;
$ua->agent("Koha ILL");

# Create a request
my $url = "https://iller.libris.kb.se/librisfjarrlan/api/illrequests/Hig/$orderid";
say "POSTing to $url";
my $request = HTTP::Request->new( 'POST', $url );
$request->header( 'api-key' => $ill_config->{ 'libris_key' } );
$request->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
$request->content( "action=response&timestamp=$timestamp&response_id=2&added_response=Test&may_reserve=0" );

# Pass request to the user agent and get a response back
my $res = $ua->request($request);

my $json;
# Check the outcome of the response
if ($res->is_success) {
    $json = $res->content;
    my $new_data = decode_json( $json );
    say Dumper $new_data;
    say "Update action:  " . $new_data->{'update_action'};
    say "Update success: " . $new_data->{'update_success'};
    say "Update message: " . $new_data->{'update_message'};
    say "Last modified:  " . $new_data->{'ill_requests'}->[0]->{'last_modified'};
    say "Status:         " . $new_data->{'ill_requests'}->[0]->{'status'};
} else {
    say $res->status_line;
}

sub get_data {

    my ( $fragment ) = @_;

    my $base_url  = 'https://iller.libris.kb.se/librisfjarrlan/api';
    my $sigil     = $ill_config->{ 'libris_sigil' };
    my $libriskey = $ill_config->{ 'libris_key' };

    # Create a user agent object
    my $ua = LWP::UserAgent->new;
    $ua->agent("Koha ILL");

    # Replace placeholders in the fragment
    $fragment =~ s/__sigil__/$sigil/g;

    # Create a request
    my $url = "$base_url/$fragment";
    say "Requesting $url";
    my $request = HTTP::Request->new( GET => $url );
    $request->header( 'api-key' => $libriskey );

    # Pass request to the user agent and get a response back
    my $res = $ua->request($request);

    my $json;
    # Check the outcome of the response
    if ($res->is_success) {
        $json = $res->content;
    } else {
        say $res->status_line;
    }

    unless ( $json ) {
        say "No JSON!";
        exit;
    }

    my $data = decode_json( $json );
    if ( $data->{'count'} == 0 ) {
        say "No data!";
        exit;
    }

    return $data;

}
