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
binmode STDOUT, ":utf8";

use Koha::Illrequests;
use Koha::Illrequest::Config;

# Get options
my ( $limit, $verbose, $debug ) = get_options();

# my $data = get_recent_data();
# We should probably use "incoming", but while developing it is more predictable
# to use "recent". Change to this before using in a live setting:
my $data = get_incoming_data(); 

say "Found $data->{'count'} requests" if $verbose;

foreach my $req ( @{ $data->{'ill_requests'} } ) {

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

    # Save or update the request in Koha
    my $old_illrequest = Koha::Illrequests->find({ orderid => $req->{'request_id'} });
    if ( $old_illrequest ) {
        say "Found an existing request with illrequest_id = " . $old_illrequest->illrequest_id if $verbose;
        # Update the request
        $old_illrequest->status( $req->{'status'} );
        $old_illrequest->store;
        # Update the attributes
        foreach my $attr ( keys %{ $req } ) {
            next if ( $attr eq 'receiving_library' || $attr eq 'recipients' || $attr eq 'end_user' );
            $old_illrequest->illrequestattributes->find({ 'type' => $attr })->update({ 'value' => $req->{ $attr } });
        }
        # $old_illrequest->illrequestattributes->find({ 'type' => 'author' })->update({ 'value' => $req->{'author'} });
        # $old_illrequest->illrequestattributes->find({ 'type' => 'isbn_issn' })->update({ 'value' => $req->{'isbn_issn'} });
    } else {
        say "Going to create a new request" if $verbose;
        my $illrequest = Koha::Illrequest->new;
        $illrequest->load_backend( 'Libris' );
        my $backend_result = $illrequest->backend_create({
            'orderid'        => $req->{'request_id'},
            'borrowernumber' => '',
            'biblio_id'      => '',
            'branchcode'     => '',
            'status'         => $req->{'status'}, 
            'placed'         => '',
            'replied'        => '',
            'completed'      => '',
            'medium'         => '',
            'accessurl'      => '',
            'cost'           => '',
            'notesopac'      => '',
            'notesstaff'     => '',
            'backend'        => 'Libris',
            'stage'          => 'commit',
            # 'attr'           => {
            #     'lf_number' => $req->{'lf_number'},
            #     'title'     => $req->{'title'},
            #     'author'    => $req->{'author'},
            #     'isbn_issn' => $req->{'isbn_issn'}
            # },
        });
        say Dumper $backend_result; # FIXME Check for no errors
        say "Created new request with illrequest_id = " . $illrequest->illrequest_id if $verbose;
        # Add attributes
        foreach my $attr ( keys %{ $req } ) {
            next if ( $attr eq 'receiving_library' || $attr eq 'recipients' || $attr eq 'end_user' );
            Koha::Illrequestattribute->new({
                illrequest_id => $illrequest->illrequest_id,
                type          => $attr,
                value         => $req->{ $attr },
            })->store;
        }
    }

#        'borrowernumber' => $borrower->{borrowernumber},
#        'biblionumber'   => $biblionumber,
#        'branchcode'     => 'ILL',
#        'status'         => 'H_ITEMREQUESTED',
#        'medium'         => $bibdata->{MediumType},
#        'backend'        => 'Libris',
#        'attr'           => {
#            'title'        => $bibdata->{Title},
#            'author'       => $bibdata->{Author},
#            'ordered_from' => $ordered_from,
#            'ordered_from_borrowernumber' => $ordered_from_patron->{borrowernumber},
#            # 'id'           => 1,
#            'PlaceOfPublication'  => $bibdata->{PlaceOfPublication},
#            'Publisher'           => $bibdata->{Publisher},
#            'PublicationDate'     => $bibdata->{PublicationDate},
#            'Language'            => $bibdata->{Language},
#            'ItemIdentifierType'  => $request->{$message}->{ItemId}->{ItemIdentifierType},
#            'ItemIdentifierValue' => $request->{$message}->{ItemId}->{ItemIdentifierValue},
#            'RequestType'         => $request->{$message}->{RequestType},
#            'RequestScopeType'    => $request->{$message}->{RequestScopeType},
#         },

}

# SUBROUTINES

sub get_incoming_data {

    return get_data( 'illrequests', 'incoming' );

}

sub get_recent_data {

    return get_data( 'illrequests', 'recent' );

}

sub get_data {

    my ( $action, $what ) = @_;

    my $base_url  = 'http://iller.libris.kb.se/librisfjarrlan/api';
    my $sigil     = 'Hig'; # FIXME Use local syspref
    my $libriskey = 'xyz'; # FIXME Use local syspref

    # Create a user agent object
    my $ua = LWP::UserAgent->new;
    $ua->agent("Koha ILL");

    # Create a request
    my $url = "$base_url/$action/$sigil/$what";
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

=head1 OPTIONS

=over 4

=item B<-l, --limit>

Only process the n first requests. Not implemented.

=item B<-v --verbose>

More verbose output.

=item B<-d --debug>

Even more verbose output.

=item B<-h, -?, --help>

Prints this help message and exits.

=back

=cut

sub get_options {

    # Options
    my $limit      = '';
    my $verbose    = '';
    my $debug      = '';
    my $help       = '';

    GetOptions (
        'l|limit=i'  => \$limit,
        'v|verbose'  => \$verbose,
        'd|debug'    => \$debug,
        'h|?|help'   => \$help
    );

    pod2usage( -exitval => 0 ) if $help;

    return ( $limit, $verbose, $debug );

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
