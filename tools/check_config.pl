#!/usr/bin/perl

# TODO Tip about:
# INSERT INTO borrowers SELECT * FROM deletedborrowers WHERE borrowernumber = 12886;
# DELETE FROM deletedborrowers WHERE borrowernumber = 12886;

use Modern::Perl;
use YAML::Syck qw( LoadFile );
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Term::ANSIColor qw( :constants );

use C4::Context;
use Koha::Patrons;

# Get the path to, and read in, the Libris ILL config file
my $config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
my $config = LoadFile( $config_file );
my $checked_config = $config;

say Dumper $config;

# Patrons
foreach my $var ( qw( unknown_patron libris_borrowernumber ) ) {

    if ( defined $config->{ $var } ) {
        my $patron = Koha::Patrons->find({ 'borrowernumber' => $config->{ $var } });
        if ( $patron ) {
            say GREEN, "OK, $var found: ", $patron->userid, RESET;
        } else {
            say RED, "$var not found!", RESET;
        }
    } else {
        say RED, "$var not defined!";
    }
    delete $checked_config->{ $var };

}

# Patron ID fields
foreach my $field ( qw( patron_id_field patron_id_field_alt ) ) {

    if ( $config->{ $field } =~ m/^userid|cardnumber|borrowernumber$/ ) {
        say GREEN, "OK, $field looks ok ($config->{ $field })", RESET;
    } else {
        say RED, "$field contains an illegal value: $config->{ $field }", RESET;
    }
    delete $checked_config->{ $field };

}

say "Not checked:";
say Dumper $checked_config;
