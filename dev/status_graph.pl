#!/usr/bin/perl

use Modern::Perl;
use Data::Dumper;
use Koha::Illbackends::Libris::Base;

my $sg = Koha::Illbackends::Libris::Base::status_graph();

say Dumper $sg;
