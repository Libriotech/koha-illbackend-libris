#!/usr/bin/perl

# Copyright 2017 Magnus Enger Libriotech

=head1 NAME

get_data_from_libris.pl - Cronjob to fetch updates from Libris.

=head1 SYNOPSIS

 sudo koha-shell -c "perl get_data_from_libris.pl -v" koha

=cut

use LWP;
use LWP::UserAgent;
use JSON qw( decode_json );
use Scalar::Util qw( reftype );
use Getopt::Long;
use Data::Dumper;
use Template;
use DateTime;
use Pod::Usage;
use Modern::Perl;
use utf8;
binmode STDOUT, ":utf8";

use C4::Context;
use Koha::Illrequests;
use Koha::Illrequest::Config;
use Koha::Illbackends::Libris::Base;

# Get options
my ( $mode, $start_date, $end_date, $limit, $refresh, $verbose, $debug, $test ) = get_options();

my $ill_config = C4::Context->config('interlibrary_loans');
say Dumper $ill_config if $debug;
foreach my $element ( qw( sigil key) ) {
    my $key = "libris_$element";
    unless ( $ill_config->{ $key } ) {
        die "You need to define '$key' in koha-conf.xml! See 'docs/config.pod' for details.\n"
    }
}

my $dbh = C4::Context->dbh;

my $data;
if ( $refresh ) {
    # Refresh all requests in the DB with fresh data
    my $old_requests = Koha::Illrequests->search({ 'backend' => 'Libris' });
    my $refresh_count = 0;
    while ( my $req = $old_requests->next ) {
        next unless $req->orderid;
        my $req_data = get_request_data( $req->orderid );
        if ( $refresh_count == 0 ) {
            # On the first pass we save the whole datastructure
            $data = $req_data;
        } else {
            # On subsequent passes we add the aqtual request data to the array in "ill_requests"
            push @{ $data->{ 'ill_requests' } }, $req_data->{ 'ill_requests' }->[0];
        }
        $refresh_count++;
        if ( $limit && $limit == $refresh_count ) {
            last;
        }
        sleep 5;
    }
    $data->{ 'count' } = $refresh_count;
} elsif( $mode && $mode eq 'outgoing' ) {
    # Get data from Libris
    my $query = "start_date=$start_date&end_date=$end_date";
    say $query if $verbose;
    $data = get_data_by_mode( $query );
} else {
    # Get data from Libris
    $data = get_data_by_mode();
}

say "Found $data->{'count'} requests" if $verbose;

REQUEST: foreach my $req ( @{ $data->{'ill_requests'} } ) {

    # Output details about the request
    say "-----------------------------------------------------------------";
    say "* $req->{'request_id'} / $req->{'lf_number'}:  $req->{'title'} ($req->{'year'})";
    say "\tAuthor:       $req->{'author'} / $req->{'imprint'} / $req->{'place_of_publication'}";
    say "\tISBN/ISSN:    $req->{'isbn_issn'}";
    say "\tRequest type: $req->{'request_type'}";
    say "\tProc. time:   $req->{'processing_time'} ($req->{'processing_time_code'})";
    say "\tDeliv. type:  $req->{'delivery_type'} ($req->{'delivery_type_code'})";
    say "\tStatus:       $req->{'status'}";
    say "\tXstatus:      $req->{'xstatus'}";
    say "\tMessage:      $req->{'message'}";
    say "\tbib_id:       $req->{'bib_id'}";
    
    my $receiving_library = $req->{'receiving_library'};
    say "\tReceiving library: $receiving_library->{'name'} ($receiving_library->{'library_code'})";

    say "\tRecipients:";
    my @recipients = @{ $req->{'recipients'} };
    foreach my $recip ( @recipients ) {
        print "\t\t$recip->{'library_code'} ($recip->{'library_id'}) | ";
        print "Location: $recip->{'location'} | ";
        if ( $recip->{'response'} ) {
            print "Response: $recip->{'response'} ($recip->{'response_date'}) | ";
        }
        print "Active: $recip->{'is_active_library'}";
        print "\n";
    }

    # Save or update data about the receiving library
    my $borrowernumber_receiving_library = upsert_receiving_library( $receiving_library->{'library_code'} );

    # Bail out if we are only testing
    if ( $test ) {
        say "We are in testing mode, so not saving any data";
        next REQUEST;
    }

    my $biblionumber = 0;
    my $status = '';
    if (
        ( $mode && $mode eq 'outgoing' ) || # For --mode outgoing
        ( $req->{ 'active_library' } ne $ill_config->{ 'libris_sigil' } ) # For --refresh
       ) {
        # Inlån (outgoing request) - We are requesting things from others, so we do not have a record for it
        # FIXME Get the record from Libris
        $status = 'IN_';
    } else {
        # Utlån (incoming requests) - Others are requesting things from us, so we should have a record for it
        if ( $req->{'bib_id'} && $req->{'bib_id'} ne '' ) {
            # Look for the bib record based on bib_id and MARC field 001
            my $hits = $dbh->selectrow_hashref( 'SELECT biblionumber FROM biblio_metadata WHERE ExtractValue( metadata,\'//controlfield[@tag="001"]\' ) = ?', undef, ( $req->{'bib_id'} ) );
            say Dumper $hits;
            $biblionumber = $hits->{'biblionumber'};
        }
        $status = 'OUT_';
    }
    $status .= Koha::Illbackends::Libris::Base::translate_status( $req->{'status'} );

    # Save or update the request in Koha
    my $old_illrequest = Koha::Illrequests->find({ orderid => $req->{'lf_number'} });
    if ( $old_illrequest ) {
        say "Found an existing request with illrequest_id = " . $old_illrequest->illrequest_id if $verbose;
        # Update the request
        $old_illrequest->status( $status );
        $old_illrequest->medium( $req->{'media_type'} );
        $old_illrequest->orderid( $req->{'lf_number'} ); # Temporary fix for updating old requests
        $old_illrequest->biblio_id( $biblionumber );
        $old_illrequest->store;
        # Update the attributes
        foreach my $attr ( keys %{ $req } ) {
            # "recipients" is an array of hashes, so we need to flatten it out
            if ( $attr eq 'recipients' ) { 
                my @recipients = @{ $req->{ 'recipients' } };
                my $recip_count = 1;
                foreach my $recip ( @recipients ) { 
                    foreach my $key ( keys %{ $recip } ) { 
                        $old_illrequest->illrequestattributes->find({ 'type' => $attr . "_$recip_count" . "_$key" })->update({ 'value' => $recip->{ $key } });
                    }
                    $recip_count++;
                } 
            } elsif ( $attr eq 'receiving_library' || $attr eq 'end_user' ) {
                my $hashref = $req->{ $attr };
                foreach my $data ( keys %{ $hashref } ) {
                    $old_illrequest->illrequestattributes->find({ 'type' => $attr . "_$data" })->update({ 'value' => $req->{ $attr }->{ $data } });
                }
            } else {
                $old_illrequest->illrequestattributes->find({ 'type' => $attr })->update({ 'value' => $req->{ $attr } });
                say "DEBUG: $attr = ", $req->{ $attr } if ( $req->{ $attr } && $debug );
            }
        }
    } else {
        say "Going to create a new request" if $verbose;
        my $illrequest = Koha::Illrequest->new;
        $illrequest->load_backend( 'Libris' );
        my $backend_result = $illrequest->backend_create({
            'orderid'        => $req->{'lf_number'},
            'borrowernumber' => $borrowernumber_receiving_library,
            'biblio_id'      => $biblionumber,
            'branchcode'     => '',
            'status'         => $status,
            'placed'         => '',
            'replied'        => '',
            'completed'      => '',
            'medium'         => $req->{'media_type'},
            'accessurl'      => '',
            'cost'           => '',
            'notesopac'      => '',
            'notesstaff'     => '',
            'backend'        => 'Libris',
            'stage'          => 'from_api',
        });
        say Dumper $backend_result; # FIXME Check for no errors
        say "Created new request with illrequest_id = " . $illrequest->illrequest_id if $verbose;
        # Add attributes
        foreach my $attr ( keys %{ $req } ) {
            # "recipients" is an array of hashes, so we need to flatten it out
            if ( $attr eq 'recipients' ) {
                my @recipients = @{ $req->{ 'recipients' } };
                my $recip_count = 1;
                foreach my $recip ( @recipients ) {
                    foreach my $key ( keys %{ $recip } ) { 
                        Koha::Illrequestattribute->new({
                            illrequest_id => $illrequest->illrequest_id,
                            type          => $attr . "_$recip_count" . "_$key",
                            value         => $recip->{ $key },
                        })->store;
                    }
                    $recip_count++;
                }
            # receiving_library and end_user are hashes, so we need to flatten them out
            } elsif ( $attr eq 'receiving_library' || $attr eq 'end_user' ) {
                my $end_user = $req->{ $attr };
                foreach my $data ( keys %{ $end_user } ) {
                    Koha::Illrequestattribute->new({
                        illrequest_id => $illrequest->illrequest_id,
                        type          => $attr . "_$data",
                        value         => $req->{ $attr }->{ $data },
                    })->store;
                }
            } else {
                Koha::Illrequestattribute->new({
                    illrequest_id => $illrequest->illrequest_id,
                    type          => $attr,
                    value         => $req->{ $attr },
                })->store;
                say "DEBUG: $attr = ", $req->{ $attr } if $debug;
            }
        }
    }

}

=head1 SUBROUTINES

=cut

sub get_data_by_mode {

    my ( $query ) = @_;

    if ( $query ) {
        # Add leading questionmark
        $query = "?$query";
    } else {
        # Avoid error of uninitialized variable later
        $query = '';
    }

    return get_data( "illrequests/__sigil__/$mode$query" );

}

sub get_request_data {

    my ( $orderid ) = @_;
    return get_data( "illrequests/__sigil__/$orderid" );

}

sub get_data {

    my ( $fragment ) = @_;

    my $base_url  = 'http://iller.libris.kb.se/librisfjarrlan/api';
    my $sigil     = $ill_config->{'libris_sigil'};
    my $libriskey = $ill_config->{'libris_key'};

    # Create a user agent object
    my $ua = LWP::UserAgent->new;
    $ua->agent("Koha ILL");

    # Replace placeholders in the fragment
    $fragment =~ s/__sigil__/$sigil/g;

    # Create a request
    my $url = "$base_url/$fragment";
    say "Requesting $url" if $verbose;
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

    say Dumper $data if $debug;

    return $data;

}

=head2 upsert_receiving_library()

Takes the sigil of a library as an argument and looks it up in the "libraries"
endpoint of the Libris API. If a library with that sigil already exists in the
Koha database, it is updated. If it does not exist, a new library is inserted,
based on the retrieved data.

The borrowernumber of the library in question is returned, either way.

=cut

sub upsert_receiving_library {

    my ( $receiver_sigil ) = @_;

    my $all_lib_data = get_data( "libraries/__sigil__/$receiver_sigil" );
    # The API returns a hash with the single key libraries, which contains an
    # array of hashes describing libraries. We should only be getting data about
    # one library back, so we pick out the first one.
    my $lib_data = $all_lib_data->{'libraries'}->[0];

    # Try to find an existing library with the given sigil
    my $library = Koha::Patrons->find({ cardnumber => $receiver_sigil });

    # Map data from the API to Koha database structure
    my $address2 = $lib_data->{'address2'};
    if ( $lib_data->{'address3'} ) {
        $address2 .= ', ' . $lib_data->{'address3'};
    }
    my $new_library_data = {
        cardnumber   => $receiver_sigil,
        surname      => $lib_data->{'name'},
        categorycode => 'ILLLIBS', # FIXME Use partner_code from the ILL config
        branchcode   => 'ILL', # FIXME
        userid       => $receiver_sigil,
        password     => '!',
        address      => $lib_data->{'address1'},
        address2     => $address2,
        city         => $lib_data->{'city'},
        zipcode      => $lib_data->{'zip_code'},
    };

    my $borrowernumber;
    if ( $library ) {
        say "*** Updating existing library" if $verbose;
        $library->update( $new_library_data );
        $borrowernumber = $library->borrowernumber;
    } else {
        say "*** Inserting new library" if $verbose;
        my $new_library = Koha::Patron->new( $new_library_data )->store();
        $borrowernumber = $new_library->borrowernumber;
    }

    return $borrowernumber;

}

=head1 OPTIONS

=over 4

=item B<-m, --mode>

This script can fetch data from endpoints, specified by this parameter. Available
options are:

=over 4

=item * recent (default)

=item * incoming

=item * may_reserve

=item * notfullfilled

=item * delivered

=item * outgoing

=back

If no mode is specified, "recent" is the default.

If "outgoing" is specified, the default date range is from "yesterday" to "today". See --start_date
and --end_date for other options.

=item B<-s, --start_date>

First day to fetch outgoing requests for. Defaults to "yesterday". Only applicable if mode=outgoing.

=item B<-e, --end_date>

Most recent day to fetch outgoing requests for. Defaults to "today". Only applicable if mode=outgoing.

=item B<-l, --limit>

Only process the n first requests. Not implemented.

=item B<-r, --refresh>

Get fresh data for all requests in the database.

=item B<-v --verbose>

More verbose output.

=item B<-d --debug>

Even more verbose output. Specifically, this option will cause all retreived data
from the API to be dumped.

=item B<-t --test>

Retrieve data, but do not try to save it.

=item B<-h, -?, --help>

Prints this help message and exits.

=back

=cut

sub get_options {

    my $dt = DateTime->now;

    # Options
    my $mode       = 'recent';
    my $end_date   = $dt->ymd; # Today
    my $start_date = $dt->subtract(days => 1)->ymd; # Yesterday
    my $limit      = '';
    my $refresh    = '';
    my $verbose    = '';
    my $debug      = '';
    my $test       = '';
    my $help       = '';

    GetOptions (
        'm|mode=s'       => \$mode,
        's|start_date=s' => \$start_date,
        'e|end_date=s'   => \$end_date,
        'l|limit=i'      => \$limit,
        'r|refresh'      => \$refresh,
        'v|verbose'      => \$verbose,
        'd|debug'        => \$debug,
        't|test'         => \$test,
        'h|?|help'       => \$help
    );

    pod2usage( -exitval => 0 ) if $help;

    # Make sure mode has a valid value
    my %mode_ok = (
        'recent' => 1,
        'incoming' => 1,
        'may_reserve' => 1,
        'notfullfilled' => 1,
        'delivered' => 1,
        'outgoing' => 1,
    );
    # FIXME Point out that the mode was invalid
    pod2usage( -exitval => 0 ) unless $mode_ok{ $mode };

    return ( $mode, $start_date, $end_date, $limit, $refresh, $verbose, $debug, $test );

}

=head1 AUTHOR

Magnus Enger, <magnus [at] libriotech.no>

=head1 LICENSE

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
