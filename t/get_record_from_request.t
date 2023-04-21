#!/usr/bin/perl

=pod

=head1 get_record_from_request

Tests for Koha::Illbackends::Libris::Base::get_record_from_request

=cut

use Modern::Perl;
use MARC::File::XML;
binmode STDOUT, ":utf8";
use utf8;

use Test::More tests => 1;
use lib ".";

BEGIN {
    use_ok('Base');
}

__END__

# Wasn't able to make this work

my $request = {
    'bib_id' => 'TEST',
    'author' => 'Testesen, Test',
    'title'  => 'My title with æøåäö',
};

my $record_from_request = Koha::Illbackends::Libris::Base::get_record_from_request( $request );
my $marcxml = '<?xml version="1.0" encoding="UTF-8"?>
<collection
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"
  xmlns="http://www.loc.gov/MARC21/slim">
<record>
  <leader>         a              </leader>
  <controlfield tag="001">TEST</controlfield>
  <datafield tag="100" ind1=" " ind2=" ">
    <subfield code="a">Testesen, Test</subfield>
  </datafield>
  <datafield tag="245" ind1=" " ind2=" ">
    <subfield code="a">My title with æøåäö</subfield>
  </datafield>
</record>
</collection>';
my $record_from_marcxml = MARC::Record->new_from_xml( $marcxml, 'UTF-8', 'MARC21' );

is( $record_from_request->title, $record_from_marcxml->title, 'titles match' );
diag( $record_from_request->title );
diag( $record_from_marcxml->title );
