#!/usr/bin/perl

# Copyright 2017 Magnus Enger Libriotech

=head1 NAME

get_data_from_libris.pl - Cronjob to fetch updates from Libris.

=head1 SYNOPSIS

 sudo koha-shell -c "perl get_data_from_libris.pl -v" koha

=cut

# Use a lockfile to make sure only one instance of this script is run at a time,
# per instance. The lockfile will be created in the directory pointed to by
# the "lockdir" setting in koha-conf.xml.
use Koha::Script -cron;
use Try::Tiny;
my $script = Koha::Script->new({ script => $0 });
try {
    $script->lock_exec;
} catch {
    die "$0 is already running\n";
};

use LWP;
use LWP::UserAgent;
use JSON qw( decode_json );
use YAML::Syck;
use Scalar::Util qw( reftype );
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Template;
use DateTime;
use Pod::Usage;
use Modern::Perl;
use utf8;
binmode STDOUT, ":utf8";
$| = 1; # Don't buffer output

use C4::Context;
use C4::Reserves qw( AddReserve );
use Koha::Illcomment;
use Koha::Illrequests;
use Koha::Illrequest::Config;
use Koha::Illbackends::Libris::Base;

# Special treatment for some metadata elements, to make them show up in the main ILL table
# Libris metadata elements on the left, Koha ILL metadata elements on the right
my %metadata_map = (
    'media_type' => 'type',
    'title_of_article' => 'article_title', # FIXME Base.pm, line 1412
    'volume_designation' => 'volume',
);

# Get options
my ( $libris_sigil, $mode, $start_date, $end_date, $limit, $refresh, $refresh_all, $verbose, $debug, $test ) = get_options();

# Get the path to, and read in, the Libris ILL config file
my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
my $ill_config = LoadFile( $ill_config_file );
say Dumper $ill_config if $debug;

# $libris_sigil will only be set if we are using $mode. If we are doing a refresh,
# it will not be set.
if ( $libris_sigil ) {

    # Make sure relevant data for the active sigil/library are easily available
    $ill_config->{ 'libris_sigil' } = $libris_sigil;
    $ill_config->{ 'libris_key' } = $ill_config->{ 'libraries' }->{ $libris_sigil }->{ 'libris_key' };

    # Check for a complete ILL config 
    foreach my $key ( qw( libris_sigil libris_key unknown_patron unknown_biblio ) ) {
        unless ( $ill_config->{ $key } ) {
            die "You need to define '$key' in the YAML config-file! See 'docs/config.pod' for details.\n"
        }
    }

}
say Dumper $ill_config if $debug;

my $dbh = C4::Context->dbh;

## Retrieve data from Libris

# We are doing a full or partial refresh
my $data;
if ( $refresh || $refresh_all ) {
    my $old_requests;
    if ( $refresh ) {
        # Only refresh requests with certain statuses
        $old_requests = Koha::Illrequests->search([ { status => 'IN_LAST' }, { status => 'IN_KANRES' }, { status => 'IN_UTEL' } ]);
    } else {
        # Refresh all requests in the DB with fresh data
        $old_requests = Koha::Illrequests->search({ 'backend' => 'Libris' });
    }
    my $refresh_count = 0;
    while ( my $req = $old_requests->next ) {
        next unless $req->orderid;
        say "Going to refresh request with illrequest_id=", $req->illrequest_id;
        # Find the sigil of the library that requested the ILL this is stoed as
        # ILL request attribute "requesting_library"
        next unless $req->extended_attributes->find({ type => 'requesting_library' });
        my $sigil = $req->extended_attributes->find({ type => 'requesting_library' })->value();
        # Use this to set the active sigil and key in the config
        $ill_config->{ 'libris_sigil' } = $sigil;
        $ill_config->{ 'libris_key' } = $ill_config->{ 'libraries' }->{ $sigil }->{ 'libris_key' };
        my $req_data = Koha::Illbackends::Libris::Base::get_request_data( $ill_config, $req->orderid );
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
# Outgoing requests, aka Inlån
} elsif( $mode && $mode eq 'outgoing' ) {
    # Get data from Libris
    my $query = "start_date=$start_date&end_date=$end_date";
    say $query if $verbose;
    $data = Koha::Illbackends::Libris::Base::get_data_by_mode( $ill_config, $mode, $query );
# All other operations
} else {
    # Get data from Libris
    $data = Koha::Illbackends::Libris::Base::get_data_by_mode( $ill_config, $mode );
}

say "Found $data->{'count'} requests" if $verbose;

REQUEST: foreach my $req ( @{ $data->{'ill_requests'} } ) {

    # If this request is marked with a "local" status we skip to the next request
    if ( Koha::Illrequests->find({ orderid => $req->{'lf_number'} }) ) {
        my $old_stat = Koha::Illrequests->find({ orderid => $req->{'lf_number'} })->status;
        next REQUEST if ( $old_stat && $old_stat eq 'IN_UTL' || $old_stat eq 'IN_RET' || $old_stat eq 'IN_AVSL' );
    }

    next REQUEST unless $req->{'request_id'};

## Output details about the request

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
    say "\tUser ID:      $req->{'user_id'}";
    
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

    # Bail out if we are only testing
    if ( $test ) {
        say "We are in testing mode, so not saving any data";
        next REQUEST;
    }

    my $biblionumber = 0;
    my $itemnumber;
    my $borrower     = 0;
    my $status       = '';
    my $is_inlan     = 0;

## Inlån (outgoing request) - We are requesting things from others, so we do not have a record for it

    if ( ( $mode && $mode eq 'outgoing' ) || ( $req->{ 'active_library' } ne $ill_config->{ 'libris_sigil' } ) ) {

        # The loan is requested by one of our own patrons, so we look up the borrowernumber from the cardnumber
        if ( $req->{'user_id'} ) {
            my $userid = $req->{'user_id'};
            $userid =~ s/ //g;
            # FIXME Do more checking of the user_id?
            say "Looking for user_id=$userid";
            $borrower = Koha::Illbackends::Libris::Base::userid2borrower( $userid );
        } else {
            # There is no userid, so use the unknown_patron
            $borrower = Koha::Patrons->find({ 'borrowernumber' => $ill_config->{ 'unknown_patron' } });
            say "Borrower not found, using unknown_patron";
        }
        if ( $borrower ) {
            say "Borrower found:" if $debug;
            say Dumper $borrower->unblessed if $debug;
        } else {
            # There is a user_id, but we could not find a borrower, so use unknown_patron
            say "Borrower not found, using unknown_patron";
            $borrower = Koha::Patrons->find({ 'borrowernumber' => $ill_config->{ 'unknown_patron' } });
        }
        # Set the prefix
        $status = 'IN_';
        $is_inlan = 1;

    } else {

## Utlån (incoming requests) - Others are requesting things from us, so we should have a record for it

        # Do we have a record identifier?
        if ( $req->{'bib_id'} && $req->{'bib_id'} ne '' ) {
            if ( $req->{'bib_id'} =~ m/^BIB/i ) {
                # We only have a made up biblio identifier (starting with BIB), so we use the dummy record
                $biblionumber = $ill_config->{ 'unknown_biblio' };
            } else {
                # Look for an actual bib record based on bib_id and MARC field 001
                $biblionumber = Koha::Illbackends::Libris::Base::recordid2biblionumber( $req->{'bib_id'} );
            }
        }
        # The loan was requested by another library, so we save or update data (from Libris) about the receiving library
        say "Looking for library_code=" . $receiving_library->{'library_code'};
        $borrower = Koha::Illbackends::Libris::Base::upsert_receiving_library( $ill_config, $receiving_library->{'library_code'} );
        say "Found borrowernumber=" . $borrower->borrowernumber;
        # Set the prefix
        $status = 'OUT_';

    }
    # Translate from the literal status to a code
    $status .= Koha::Illbackends::Libris::Base::translate_status( $req->{'status'} );

## Save or update the request in Koha

    # Look for the Libris order number
    my $old_illrequest = Koha::Illrequests->find({ orderid => $req->{'lf_number'} });
    if ( $old_illrequest and defined $old_illrequest->borrowernumber ) {
        # Patron is already connected to an old ill request
        $borrower = Koha::Patrons->find( $old_illrequest->borrowernumber )
    }

    # Home branch of created items
    my $homebranch;
    my $holdingbranch;
    if ( defined $ill_config->{ 'item_homebranch_equals_ill_branch' } && $ill_config->{ 'item_homebranch_equals_ill_branch' } == 1 ) {
        $homebranch    = defined $ill_config->{ 'ill_branch' } ? $ill_config->{ 'ill_branch' } : $borrower->branchcode;
        $holdingbranch = defined $ill_config->{ 'ill_branch' } ? $ill_config->{ 'ill_branch' } : $borrower->branchcode;
    } else {
        $homebranch    = $borrower->branchcode;
        $holdingbranch = $borrower->branchcode;
    }

    # We have an old request, so we update it
    if ( $old_illrequest ) {
        say "Found an existing request with illrequest_id = " . $old_illrequest->illrequest_id if $verbose;
        # Check if we should skip this request
        if ( $old_illrequest->status eq 'IN_ANK' ) {
            warn "Request is already received";
            next REQUEST;
        }
        # Update the record
        ( $biblionumber, $itemnumber ) = Koha::Illbackends::Libris::Base::upsert_record( $ill_config, 'update', $req, $homebranch, $holdingbranch, $old_illrequest );
        # Make a comment if the status changed
        if ( $status ne $old_illrequest->status ) {
            my $sg = Koha::Illbackends::Libris::Base::status_graph();
            my $old_status = $sg->{ $old_illrequest->status }->{ 'name' };
            my $new_status = $sg->{ $status                 }->{ 'name' };
            my $comment = Koha::Illcomment->new({
                illrequest_id  => $old_illrequest->illrequest_id,
                borrowernumber => $ill_config->{ 'libris_borrowernumber' },
                comment        => "Status ändrad från $old_status till $new_status.",
            });
            $comment->store();
            say "New status: $status" if $debug;
        }
        # Update the request
        $old_illrequest->status( $status );
        $old_illrequest->medium( $req->{'media_type'} );
        $old_illrequest->orderid( $req->{'lf_number'} ); # Temporary fix for updating old requests
        $old_illrequest->biblio_id( $biblionumber );
        say "Saving borrowernumber=" . $borrower->borrowernumber;
        $old_illrequest->borrowernumber( $borrower->borrowernumber );
        # $old_illrequest->branchcode( $borrower->branchcode ); Could be edited manually
        $old_illrequest->store;
        say "Connected to biblionumber=$biblionumber";
        # Update the attributes
        insert_or_update_attributes($old_illrequest, $req);
        # Check if there is a reserve, if not add one (only for Inlån and loans, not copies)
        if ( ( $is_inlan && $is_inlan == 1 ) && $req->{'media_type'} eq 'Lån' ) {
            my $res = Koha::Holds->find({ borrowernumber => $borrower->borrowernumber, biblionumber => $biblionumber });
            if ( $res ) {
                say "Found an old reserve with reserve_id=", $res->reserve_id;
            } else {
                say "Reserve NOT FOUND! Going to add one for branchcode=", $borrower->branchcode, " borrowernumber=", $borrower->borrowernumber, " biblionumber=$biblionumber";
                my $reserve_id;
                if (C4::Context->preference("Version") > 20) {
                    if ( defined $ill_config->{ 'item_level_holds' } && $ill_config->{ 'item_level_holds' } == 1 ) {
                        $reserve_id = AddReserve( {
                            branchcode => $borrower->branchcode,
                            borrowernumber => $borrower->borrowernumber,
                            biblionumber => $biblionumber,
                            itemnumber => $itemnumber,
                        } );
                    } else {
                        $reserve_id = AddReserve( {
                            branchcode => $borrower->branchcode,
                            borrowernumber => $borrower->borrowernumber,
                            biblionumber => $biblionumber,
                        } );
                    }
                } else {
                    $reserve_id = AddReserve( $borrower->branchcode, $borrower->borrowernumber, $biblionumber );
                }
                say "Reserve added with reserve_id=$reserve_id";
            }
        }
    # We do not have an old request, so we create a new one
    } else {
        # Create a record
        my $borrower_branchcode = '';
        if ( $borrower ) {
            $borrower_branchcode = $borrower->branchcode;
        }
        ( $biblionumber, $itemnumber ) = Koha::Illbackends::Libris::Base::upsert_record( $ill_config, 'insert', $req, $homebranch, $holdingbranch );
        # Create the request
        say "Going to create a new request" if $verbose;
        my $illrequest = Koha::Illrequest->new;
        $illrequest->load_backend( 'Libris' );
        my $backend_result = $illrequest->backend_create({
            'orderid'        => $req->{'lf_number'},
            'borrowernumber' => $borrower->borrowernumber,
            'biblio_id'      => $biblionumber,
            'branchcode'     => $borrower->branchcode,
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
        insert_or_update_attributes($illrequest, $req);
        # Add a hold, but only for Inlån and for loans, not copies
        if ( $is_inlan && $is_inlan == 1 && $req->{'media_type'} eq 'Lån' ) {
            my $reserve_id;
            if (C4::Context->preference("Version") > 20) {
                if ( defined $ill_config->{ 'item_level_holds' } && $ill_config->{ 'item_level_holds' } == 1 ) {
                    $reserve_id = AddReserve( {
                        branchcode => $borrower->branchcode,
                        borrowernumber => $borrower->borrowernumber,
                        biblionumber => $biblionumber,
                        itemnumber => $itemnumber,
                    } );
                } else {
                    $reserve_id = AddReserve( {
                        branchcode => $borrower->branchcode,
                        borrowernumber => $borrower->borrowernumber,
                        biblionumber => $biblionumber,
                    } );
                }
            } else {
                $reserve_id = AddReserve( $borrower->branchcode, $borrower->borrowernumber, $biblionumber );
            }
            say "Reserve added with reserve_id=$reserve_id";
        }
    }

}

sub insert_or_update_attributes {
    my $illrequest = shift;
    my $req = shift;

    my %existing = ();

    say "DEBUG: insert_or_update_attributes " . $req->{ 'lf_number' } if $debug;

    my $a = $illrequest->extended_attributes;
    while (my $attr = $a->next) {
	$existing{$attr->type} = 0;
    }

    foreach my $attr ( keys %{ $req } ) {
	if ( $attr eq 'recipients' ) {
	    my @recipients = @{ $req->{ 'recipients' } };
	    my $recip_count = 1;
	    foreach my $recip ( @recipients ) {
		foreach my $key ( keys %{ $recip } ) {
		    $existing{$attr . "_$recip_count" . "_$key"} = 1;
		    insert_or_update_attribute(
			$illrequest,
			$attr . "_$recip_count" . "_$key",
			$recip->{ $key });
		}
		$recip_count++;
	    }
            # receiving_library and end_user are hashes, so we need to flatten them out
	} elsif ( $attr eq 'receiving_library' || $attr eq 'end_user' ) {
	    my $end_user = $req->{ $attr };
	    foreach my $data ( keys %{ $end_user } ) {
		$existing{$attr . "_$data"} = 1;
		insert_or_update_attribute(
		    $illrequest,
		    $attr . "_$data",
		    $req->{ $attr }->{ $data });
	    }
	} else {
	    # Add lf_number (Libris ILL request ID) at the end of the title. This is a workaround while we wait for
	    # Koha Bug 21834 - Display illrequests.orderid in the table of ILL requests
	    if ( $attr eq 'title' ) {
		$illrequest->{ 'title' } .= ' [' . $req->{ 'lf_number' } . ']';
	    }
	    $existing{$attr} = 1;
	    insert_or_update_attribute(
		$illrequest,
		$attr,
		$req->{ $attr });
	}
	# Special treatment for some metadata elements, to make them show up in the main ILL table
	# Only add if we have a mapping from the Libris metadata
	if ( defined $metadata_map{ $attr } ) {
	    $existing{$metadata_map{ $attr }} = 1;
	    insert_or_update_attribute(
		$illrequest,
		$metadata_map{ $attr },
		$req->{ $attr });
	}
    }

    foreach my $attr (keys %existing) {
	if (!$existing{$attr}) {
	    insert_or_update_attribute($illrequest, $attr, undef);
	}
    }
}

sub insert_or_update_attribute {
    my ($illrequest, $attribute, $value) = @_;


    my $existing = $illrequest->extended_attributes->find(
	{
	    illrequest_id => $illrequest->illrequest_id,
	    type => $attribute
	});

    if (defined $existing) {
	if (!defined $value) {
	    say "DEBUG: $attribute is null deleting " if  $debug;
	    $existing->delete;
	} else {
	    say "DEBUG: updating $attribute = ", $value if $debug;
	    $existing->value($value)->store;
	}
    } else {
	if (!defined $value) {
	    say "DEBUG: $attribute is null ignoring " if  $debug;
	} else {
	    say "DEBUG: inserting $attribute = ", $value if $debug;
	    Koha::ILL::Request::Attribute->new(
		{
		    illrequest_id => $illrequest->illrequest_id,
		    type => $attribute,
		    value => $value
		})->store;
	}
    }
}

=head1 OPTIONS

=over 4

=item B<--sigil>

Which of the sigils defined in the configfile should we fetch data for?

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

Get fresh data for requests with certain statuses in the database. This should
catch requests that fall outside the --start_date and --end_date range.

=item B<-a, --refresh_all>

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
    my $libris_sigil = '';
    my $mode         = 'recent';
    my $end_date     = $dt->ymd; # Today
    my $start_date   = $dt->subtract(days => 1)->ymd; # Yesterday
    my $limit        = '';
    my $refresh      = '';
    my $refresh_all  = '';
    my $verbose      = '';
    my $debug        = '';
    my $test         = '';
    my $help         = '';

    GetOptions (
        'sigil=s'        => \$libris_sigil,
        'm|mode=s'       => \$mode,
        's|start_date=s' => \$start_date,
        'e|end_date=s'   => \$end_date,
        'l|limit=i'      => \$limit,
        'r|refresh'      => \$refresh,
        'a|refresh_all'  => \$refresh_all,
        'v|verbose'      => \$verbose,
        'd|debug'        => \$debug,
        't|test'         => \$test,
        'h|?|help'       => \$help
    );

    pod2usage( -exitval => 0 ) if $help;

    if ( $refresh && $libris_sigil ) {
        pod2usage( -msg => "\n--refresh and --sigil can not be specified at the same time.\n", -exitval => 0 );
    }

    if ( !$refresh && !$libris_sigil ) {
        pod2usage( -msg => "\nIf you are not doing a --refresh, you must specify --mode and --sigil.\n", -exitval => 0 );
    }

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

    return ( $libris_sigil, $mode, $start_date, $end_date, $limit, $refresh, $refresh_all, $verbose, $debug, $test );

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
