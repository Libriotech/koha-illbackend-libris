#!/usr/bin/perl

use Modern::Perl;
use YAML::Syck;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use Koha::Illbackends::Libris::Base;

my $request_id = $ARGV[0];
die "Usage: $0 <request_id>" unless $request_id;
say "Looking up $request_id";

# Get the path to, and read in, the Libris ILL config file
my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
my $ill_config = LoadFile( $ill_config_file );
say Dumper $ill_config;

# Get the sigil from the request_id and add it to the config in the place
# where get_request_data() expects to find it.
$request_id =~ m/(.*?)-.*/i;
$ill_config->{ 'libris_sigil' } = $1;

my $data = Koha::Illbackends::Libris::Base::get_request_data( $ill_config, $request_id );
say Dumper $data;
