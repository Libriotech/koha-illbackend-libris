#!/usr/bin/perl

use Modern::Perl;
use Encode;
use Getopt::Long;
use Pod::Usage;
use DateTime;
use YAML::Syck;
use Data::Dumper;
use utf8;
$| = 1; # Don't buffer output

use Koha::Checkouts;
use Koha::DateUtils qw( dt_from_string );
use Koha::Illrequests;
use Koha::Illrequestattributes;
use Koha::Illbackends::Libris::Base;
use Koha::Items;
use Koha::Notice::Messages;
use Koha::Patrons;
use C4::Context;
use C4::Letters;
binmode(STDOUT, ":utf8");

my ($skip_issues_check, $verbose) = get_options();

print "Execution started at " . DateTime->now->iso8601 . "\n" if $verbose;

my $dbh = C4::Context->dbh;

# Get the path to, and read in, the Libris ILL config file
my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
my $ill_config = LoadFile( $ill_config_file );
my $reminders = $ill_config->{ 'reminders' };

# find received inter library loans
my $receiveds = Koha::Illrequests->search({
    status => 'IN_ANK'
});

my $now = DateTime->now;

foreach my $received ( $receiveds->as_list ) {
    my $type = Koha::Illrequestattributes->find({
        illrequest_id => $received->illrequest_id,
        type => 'type'
    });
    next unless $type;
    $type = Encode::encode( 'utf8', $type->value );

    next unless exists $reminders->{ $type };

    # check if issued to patron
    my $item = Koha::Items->find({ biblionumber => $received->biblio_id });
    unless ($skip_issues_check) {
        my $issues = Koha::Checkouts->search({
            itemnumber => $item->itemnumber,
            borrowernumber => $received->borrowernumber,
        });
        next if $issues->count;
    }

    # When was the request received? Letters configured in $illconfig->{'reminders}
    # will be based on this date
    my $date_received = Koha::Illrequestattributes->search({
        illrequest_id => $received->illrequest_id,
        type => 'date_received'
    })->next;
    next unless $date_received;

    $date_received = $date_received->value;

    # How many reminders have we sent so far? This will determine which letter
    # will be used.
    my $reminder_count = Koha::Illrequestattributes->find({
        illrequest_id => $received->illrequest_id,
        type => 'notified_reminder_count'
    });
    $reminder_count = $reminder_count ? $reminder_count->value : 0;

    my $sent_reminder = 0;

    # check if next reminder is defined
    if ( ref( $reminders->{ $type } ) eq 'ARRAY' and
        scalar @{ $reminders->{ $type } } > ( $reminder_count ) )
    {
        my $reminder = $reminders->{ $type }->[$reminder_count];

        # has enough time passed to send next reminder?
        my $days_passed = dt_from_string( $date_received )->
            delta_days( $now )->in_units('days');

        if ( $days_passed >= $reminder->{'days_after'} ) {
            my $patron = Koha::Patrons->find( $received->borrowernumber );
            my $letter_code = $reminder->{'letter_code'};

            my $mtts = _find_effective_template({
                module => 'ill',
                code => $letter_code,
                branchcode => $patron->branchcode,
                lang => $patron->lang,
            });

            unless ( $mtts->count ) {
                warn 'No supported message transport types for '.
                    "letter '$letter_code'";
            }

            foreach my $mtt ( $mtts->as_list ) {
                my $absolute_mtt = $mtt->message_transport_type;
                $absolute_mtt =~ s/notified_mtt_//g;

                my $letter = C4::Letters::GetPreparedLetter (
                    module => 'ill',
                    letter_code => $letter_code,
                    message_transport_type => $absolute_mtt,
                    branchcode => $patron->branchcode,
                    lang => $patron->lang,
                    tables => {
                        'biblio', $item->biblionumber,
                        'biblioitems', $item->biblionumber,
                        'borrowers', $patron->borrowernumber,
                    },
                );

                C4::Letters::EnqueueLetter({
                    letter                 => $letter,
                    borrowernumber         => $patron->borrowernumber,
                    message_transport_type => $absolute_mtt,
                });

                $sent_reminder = 1;
                print "sent '$letter_code' with '$absolute_mtt' to " .
                    $patron->borrowernumber . "\n" if $verbose;
            }

        }
    }
    if ( $sent_reminder ) {
        my $notified_reminder_count = Koha::Illrequestattributes->find({
                illrequest_id => $received->illrequest_id,
                type => 'notified_reminder_count'
            });
        if ( $notified_reminder_count ) {
            Koha::Illrequestattributes->find({
                illrequest_id => $received->illrequest_id,
                type => 'notified_reminder_count'
            })->update({ value => ++$reminder_count })->store
        } else {
            Koha::Illrequestattribute->new({
                illrequest_id => $received->illrequest_id,
                type => 'notified_reminder_count',
                value => ++$reminder_count
            })->store;
        }
    }
}

print "Execution ended at " . DateTime->now->iso8601 . "\n" if $verbose;

# from Koha::Notice::Templates return all templates instead of first found
sub _find_effective_template {
    my ( $params ) = @_;

    $params = { %$params }; # don't modify original

    $params->{lang} = 'default'
      unless C4::Context->preference('TranslateNotices') && $params->{lang};

    my $only_my_library = C4::Context->only_my_library;
    if ( $only_my_library and $params->{branchcode} ) {
        $params->{branchcode} = C4::Context::mybranch();
    }
    $params->{branchcode} //= '';
    $params->{branchcode} = [$params->{branchcode}, ''];

    my $template = Koha::Notice::Templates->search( $params, { order_by => { -desc => 'branchcode' } } );

    if (   !$template->count
        && C4::Context->preference('TranslateNotices')
        && $params->{lang} ne 'default' )
    {
        $params->{lang} = 'default';
        $template = Koha::Notice::Templates->( $params, { order_by => { -desc => 'branchcode' } } );
    }

    return $template;
}

=head1 OPTIONS

=over 4

=item B<--skip-issues-check>

When given, the script does not check issues table for patron's checkouts. It is
not necessary to query issues if this script is executed after
cron/circstatus2illstatus.pl

=item B<-v, --verbose>

Adds verbosity.

=item B<-h, -?, --help>

Prints this help message and exits.

=back

=cut

sub get_options {

    my $dt = DateTime->now;

    # Options
    my $help               = '';
    my $skip_issues_check;
    my $verbose;

    GetOptions (
        'h|?|help'          => \$help,
        'skip-issues-check' => \$skip_issues_check,
        'v|verbose'         => \$verbose,
    );

    pod2usage( -exitval => 0 ) if $help;

    return ( $skip_issues_check, $verbose );
}

=head1 AUTHOR

Lari Taskula, <lari.taskula [at] hypernova.fi>

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
