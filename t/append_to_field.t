#!/usr/bin/perl

=pod

=head1 _append_to_field

Tests for Koha::Illbackends::Libris::Base::_append_to_field

=cut

use Modern::Perl;

use Test::More tests => 3;
use lib ".";

BEGIN {
    use_ok('Base');
}

my $old_title  = 'My title';
my $added_text = 'Some text';
my $new_title  = "$old_title [ $added_text ]";
my $subtitle   = 'The subtitle';

my $record = MARC::Record->new();
my $old_field = MARC::Field->new( '245', ' ', ' ',
    'a' => $old_title,
    'b' => $subtitle,
);
$record->insert_fields_ordered( $old_field );

# Update the title and make sure the new one is what we expect it to be

my $old_value = $record->subfield( '245', 'a' );

$record = Koha::Illbackends::Libris::Base::_append_to_field( $record, '245', 'a', $added_text );

my $new_title_from_record = $record->subfield( '245', 'a' );

is( $new_title_from_record, $new_title, 'title was updated' );

# Make sure the subtitle is intact

my $subtitle_from_record = $record->subfield( '245', 'b' );

is( $subtitle_from_record, $subtitle, 'subtitle is unchanged' );
