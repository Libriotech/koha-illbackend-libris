package Koha::Illbackends::Libris::Base;

# Copyright Libriotech 2017
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;
use DateTime;
use JSON qw( decode_json );
use YAML::Syck;
use LWP::UserAgent;
use LWP::Simple;
use HTTP::Request;
use Data::Dumper;

use C4::Biblio;
use C4::Context;
use C4::Letters;
use C4::Message;
use Koha::Illrequestattribute;
use Koha::Patrons;
use Koha::Item;
use Koha::Items;
use utf8;

=pod

=encoding UTF8

=head1 NAME

Koha::Illbackends::Libris::Base - Koha ILL Backend for Libris ILL (used in Sweden)

=head1 SYNOPSIS

Koha ILL implementation for the "Libris" backend.

=head1 DESCRIPTION

=head2 Overview

We will be providing the Abstract interface which requires we implement the
following methods:
- create        -> initial placement of the request for an ILL order
- confirm       -> confirm placement of the ILL order
- renew         -> request a currently borrowed ILL be renewed in the backend
- update_status -> ILL module update hook: custom actions on status update
- cancel        -> request an already 'confirm'ed ILL order be cancelled
- status        -> request the current status of a confirmed ILL order
- status_graph  -> return a hashref of additional statuses

Each of the above methods will receive the following parameter from
Illrequest.pm:

  {
      request    => $request,
      other      => $other,
  }

where:

- $REQUEST is the Illrequest object in Koha.  It's associated
  Illrequestattributes can be accessed through the `illrequestattributes`
  method.
- $OTHER is any further data, generally provided through templates .INCs

Each of the above methods should return a hashref of the following format:

    return {
        error   => 0,
        # ^------- 0|1 to indicate an error
        status  => 'result_code',
        # ^------- Summary of the result of the operation
        message => 'Human readable message.',
        # ^------- Message, possibly to be displayed
        #          Normally messages are derived from status in INCLUDE.
        #          But can be used to pass API messages to the INCLUDE.
        method  => 'status',
        # ^------- Name of the current method invoked.
        #          Used to load the appropriate INCLUDE.
        stage   => 'commit',
        # ^------- The current stage of this method
        #          Used by INCLUDE to determine HTML to generate.
        #          'commit' will result in final processing by Illrequest.pm.
        next    => 'illview'|'illlist',
        # ^------- When stage is 'commit', should we move on to ILLVIEW the
        #          current request or ILLLIST all requests.
        value   => {},
        # ^------- A hashref containing an arbitrary return value that this
        #          backend wants to supply to its INCLUDE.
    };

=head1 API

=head2 Class Methods

=cut

=head3 new

  my $backend = Koha::Illbackends::Libris::Base->new;

=cut

sub new {
    # -> instantiate the backend
    my ( $class ) = @_;
    my $self = {};
    bless( $self, $class );
    return $self;
}

sub name {
    return "Libris";
}

=head3 metadata

Return a hashref containing canonical values from the key/value
illrequestattributes store.

=cut

sub metadata {
    my ( $self, $request ) = @_;
    my $attrs = $request->illrequestattributes;

    my $return;
    $return->{'Title'}
        = $attrs->find({type => 'title'})
        ? $attrs->find({type => 'title'})->value
        : '';
    $return->{'Author'}
        = $attrs->find({type => 'author'})
        ? $attrs->find({type => 'author'})->value
        : '';
    $return->{'Xstatus'}
        = $attrs->find({type => 'xstatus'})
        ? $attrs->find({type => 'xstatus'})->value
        : 'Okänd status';
    $return->{'Libris best.nr'}
        = $attrs->find({type => 'lf_number'})
        ? $attrs->find({type => 'lf_number'})->value
        : '';
    $return->{'Request ID'}
        = $attrs->find({type => 'request_id'})
        ? $attrs->find({type => 'request_id'})->value
        : '';
    $return->{'Typ'}
        = $attrs->find({type => 'media_type'})
        ? $attrs->find({type => 'media_type'})->value
        : '';
    $return->{'År'}
        = $attrs->find({type => 'year'})
        ? $attrs->find({type => 'year'})->value
        : '';
    $return->{'ISBN/ISSN'}
        = $attrs->find({type => 'isbn_issn'})
        ? $attrs->find({type => 'isbn_issn'})->value
        : '';
    $return->{'Melding'}
        = $attrs->find({type => 'message'})
        ? $attrs->find({type => 'message'})->value
        : '';
    $return->{'Aktivt bibliotek'}
        = $attrs->find({type => 'active_library'})
        ? $attrs->find({type => 'active_library'})->value
        : '';
    $return->{'Lånetid, garanterad'}
        = $attrs->find({type => 'due_date_guar'})
        ? $attrs->find({type => 'due_date_guar'})->value
        : '';
    $return->{'Lånetid, max'}
        = $attrs->find({type => 'due_date_max'})
        ? $attrs->find({type => 'due_date_max'})->value
        : '';

    if ( $return->{'Typ'} eq 'Kopia' ) {

        # journal_article = volume_designation + pages + author_of_article + title_of_article
        # We could probably use either journal_article *or* the other ones

        $return->{'Detaljer'}
            = $attrs->find({type => 'journal_article'})
            ? $attrs->find({type => 'journal_article'})->value
            : '';
        $return->{'Sidor'}
            = $attrs->find({type => 'pages'})
            ? $attrs->find({type => 'pages'})->value
            : '';
        $return->{'Author of article'}
            = $attrs->find({type => 'author_of_article'})
            ? $attrs->find({type => 'author_of_article'})->value
            : '';
        $return->{'Title of article'}
            = $attrs->find({type => 'title_of_article'})
            ? $attrs->find({type => 'title_of_article'})->value
            : '';
        $return->{'Volum'}
            = $attrs->find({type => 'volume_designation'})
            ? $attrs->find({type => 'volume_designation'})->value
            : '';

    }

    return $return;
}

=head2 translate_status

  my $code = translate_status( $raw_status );

Takes the raw/literal status given by the Libris API and returns a
code corresponding to the status. These codes are then given names
again in Koha::Illbackends::Libris::Base::status_graph().

The codes listed here will be prefixed with IN_ or OUT_ to form the
complete status code.

=cut

sub translate_status {

    my ( $raw_status ) = @_;
    my %map = (
        'Kan reserveras' => 'KANRES', # Can be reserved
        'Reservation'    => 'RES',    # Requesting library has requested a reservation
        'Negativt svar'  => 'NEG',    # Negative answer
        'Levererad'      => 'LEV',    # Delivered
        'Läst'           => 'LAST',   # Read
        'Reserverad'     => 'RESAD',  # Reserved
        'Uteliggande'    => 'UTEL',   # Waiting
        'Remitterad'     => 'REM',
        'Avbeställd'     => 'AVBEST', # Cancelled
        'Makulerad'      => 'MAK',    # Maculated?
    );
    return $map{ $raw_status };

}


=head3 status_graph

The icons refered to here are Font Awesome icons, see L<https://fontawesome.com/v4.7.0/icons/> for a list.

=cut

sub status_graph {
    return {

        ### Outgoing ###
        OUT_LEV => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'OUT_LEV',                   # ID of this status
            name           => 'Utlån Levererad',                   # UI name of this status
            ui_method_name => 'Levererad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        OUT_KANRES => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'OUT_KANRES',                   # ID of this status
            name           => 'Utlån Kan reserveras',                   # UI name of this status
            ui_method_name => 'Kan reserveras',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        OUT_NEG => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'OUT_NEG',                   # ID of this status
            name           => 'Utlån Negativt svar',                   # UI name of this status
            ui_method_name => 'Negativt svar',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        OUT_LEV => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'OUT_LEV',                   # ID of this status
            name           => 'Utlån Levererad',                   # UI name of this status
            ui_method_name => 'Levererad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        OUT_RESAD => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'OUT_RESAD',                   # ID of this status
            name           => 'Utlån Reserverad',                   # UI name of this status
            ui_method_name => 'Reserverad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        OUT_UTEL => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'OUT_UTEL',                   # ID of this status
            name           => 'Utlån Uteliggande',                   # UI name of this status
            ui_method_name => 'Uteliggande',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'OUT_LAST' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        OUT_LAST => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'OUT_LAST',                   # ID of this status
            name           => 'Utlån Läst',                   # UI name of this status
            ui_method_name => 'Läst',                   # UI name of method leading
                                                           # to this status
            method         => 'set_status_read',                    # method to this status
            next_actions   => [ ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },

        ### Incoming ###
        IN_REM => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_REM',                   # ID of this status
            name           => 'Inlån Remitterad',                   # UI name of this status
            ui_method_name => 'Remitterad',                   # UI name of method leading
                                                           # to this status
            method         => 'create',                    # method to this status
            next_actions   => [ 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-plus',                   # UI Style class
        },
        IN_UTEL => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_UTEL',                   # ID of this status
            name           => 'Inlån Uteliggande',                   # UI name of this status
            ui_method_name => 'Uteliggande',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'IN_LAST', 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        IN_LEV => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_LEV',                   # ID of this status
            name           => 'Inlån Levererad',                   # UI name of this status
            ui_method_name => 'Levererad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        IN_ANK => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_ANK',                   # ID of this status
            name           => 'Inlån Ankommen',                   # UI name of this status
            ui_method_name => 'Ankomstregistrera',                   # UI name of method leading
                                                           # to this status
            method         => 'receive',                    # method to this status
            next_actions   => [ 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-inbox',                   # UI Style class
        },
        IN_LAST => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_LAST',                   # ID of this status
            name           => 'Inlån Läst',                   # UI name of this status
            ui_method_name => 'Läst',                   # UI name of method leading
                                                           # to this status
            method         => 'set_status_read',                    # method to this status
            next_actions   => [ 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-check-square-o',                   # UI Style class
        },
        IN_KANRES => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_KANRES',                   # ID of this status
            name           => 'Inlån Kan reserveras',                   # UI name of this status
            ui_method_name => 'Kan reserveras',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "IN_MAK" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_MAK',                   # ID of this status
            name           => 'Makulerad',                   # UI name of this status
            ui_method_name => 'Makulerad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        IN_NEG => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_NEG',                   # ID of this status
            name           => 'Inlån Negativt svar',                   # UI name of this status
            ui_method_name => 'Negativt svar',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "IN_RES" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_RES',                   # ID of this status
            name           => 'Inlån Reservation',                   # UI name of this status
            ui_method_name => 'Reservation',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        IN_RESAD => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_RESAD',                   # ID of this status
            name           => 'Inlån Reserverad',                   # UI name of this status
            ui_method_name => 'Reserverad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'IN_ANK', 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "IN_RESPONSE" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_RESPONSE',                   # ID of this status
            name           => 'Respondera',                   # UI name of this status
            ui_method_name => 'Respondera',                   # UI name of method leading
                                                           # to this status
            method         => 'respond',                    # method to this status
            next_actions   => [ 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "IN_UTL" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_UTL',                   # ID of this status
            name           => 'Inlån Utlånad',                   # UI name of this status
            ui_method_name => 'Utlånad',                   # UI name of method leading
                                                           # to this status
            method         => 'respond',                    # method to this status
            next_actions   => [ 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "IN_RET" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_RET',                   # ID of this status
            name           => 'Inlån Återlämnad',                   # UI name of this status
            ui_method_name => 'Innleverad',                   # UI name of method leading
                                                           # to this status
            method         => 'respond',                    # method to this status
            next_actions   => [ 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "IN_AVBEST" => {
            prev_actions   => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_AVBEST',                   # ID of this status
            name           => 'Inlån Avbeställd',                   # UI name of this status
            ui_method_name => 'Avbeställd',                   # UI name of method leading
                                                           # to this status
            method         => '',                    # method to this status
            next_actions   => [ 'IN_AVSL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-stop',                   # UI Style class
        },
        "IN_AVSL" => {
            prev_actions => [ 'IN_RET', 'IN_ANK' ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'IN_AVSL',                   # ID of this status
            name           => 'Inlån Avslutad',                   # UI name of this status
            ui_method_name => 'Avsluta',                   # UI name of method leading
                                                           # to this status
            method         => 'close',                    # method to this status
            next_actions   => [ ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-stop',                   # UI Style class
        },
    };
}

sub close {

    my ( $self, $params ) = @_;
    my $stage = $params->{other}->{stage};
    my $request = $params->{request};
    my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
    my $ill_config = LoadFile( $ill_config_file );
    my $sg = Koha::Illbackends::Libris::Base::status_graph();

    # Remove any holds (If we are clsoing a request that was never picked up there
    # should be a hold. If we are closing a request that has been on loan to a patron
    # and then returned there should not be one.)
    my $holds = Koha::Holds->search({ biblionumber => $request->biblio_id });
    while ( my $hold = $holds->next ) {
        $hold->delete;
    }

    # Update and delete the items connected to the the biblio connected to the request
    # (There should only be one item, but we do a loop to be on the safe side)
    my $ill_closed_itemtype = $ill_config->{ 'ill_closed_itemtype' };
    my $items = Koha::Items->search({ biblionumber => $request->biblio_id });
    while ( my $item = $items->next ) {
        # Change the itemtype to something that says e.g. "Closed ILL"
        $item->itype( $ill_closed_itemtype );
        # Set the item to "not for loan"
        $item->notforloan( 1 );
        # Remove the barcode (we might ILL the same item with the same barcode later)
        $item->barcode( undef );
        # Save the changes
        $item->store;
        # Delete the item
        $item->delete;
    }
    # Delete the record
    my $error = DelBiblio( $request->biblio_id );

    # Update the illrequest
    # The status given to requests here should result in the requests being hidden
    # from the regular view in the staff client
    my $old_status_name = $sg->{ $request->status }->{ 'name' };
    my $new_status_name = $sg->{ 'IN_AVSL' }->{ 'name' };
    $request->status( 'IN_AVSL' );
    # Anonymize (replace actual borrowernumber with that of anonymous patron)
    my $anon = C4::Context->preference( 'AnonymousPatron' );
    $request->borrowernumber( $anon );
    # Save the changes
    $request->store;
    # Add a comment
    my $comment = Koha::Illcomment->new({
        illrequest_id  => $request->illrequest_id,
        borrowernumber => $ill_config->{ 'libris_borrowernumber' },
        comment        => "Status ändrad från $old_status_name till $new_status_name.",
    });
    $comment->store();

    # Ill request attributes that should be anonymized
    my @anon_fields = qw(
        end_user_library_card
        end_user_address
        end_user_approved_by
        end_user_city
        end_user_email
        end_user_first_name
        end_user_institution
        end_user_institution_delivery
        end_user_institution_phone
        end_user_last_name
        end_user_library_card
        end_user_mobile
        end_user_phone
        end_user_user_id
        end_user_zip_code
        enduser_id
        libris_enduser_request_id
        user
        user_id
    );
    foreach my $field ( @anon_fields ) {
        if ( $request->illrequestattributes->find({ 'type' => $field }) ) {
            $request->illrequestattributes->find({ 'type' => $field })->update({ 'value' => '' });
        }
    }

    # Return to illview
    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'receive',
        stage   => 'commit',
        next    => 'illview',
    };

}

sub receive {

    my ( $self, $params ) = @_;
    my $stage = $params->{other}->{stage};
    my $request = $params->{request};

    my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
    my $ill_config = LoadFile( $ill_config_file );

    my $patron = Koha::Patrons->find({ borrowernumber => $request->borrowernumber });

    if ( $stage && $stage eq 'receive' ) {

        ## Do the actual receiving of something

        # Possibly update parts of the request and the attributes
        $request->medium(         $params->{ 'other' }->{ 'type' } );
        $request->borrowernumber( $params->{ 'other' }->{ 'borrowernumber' } );
        $request->illrequestattributes->find({ 'type' => 'media_type' })->update({ 'value' => $params->{ 'other' }->{ 'type' } });
        if ( $request->illrequestattributes->find({ type => 'type' }) && $request->illrequestattributes->find({ type => 'type' })->value ) {
            $request->illrequestattributes->find({ 'type' => 'type' })->update({ 'value' => $params->{ 'other' }->{ 'type' } });
        } else {
            Koha::Illrequestattribute->new({
                illrequest_id => $request->illrequest_id,
                type          => 'type',
                value         => $params->{ 'other' }->{ 'type' },
            })->store;
        }
        $request->illrequestattributes->find({ 'type' => 'active_library' })->update({ 'value' => $params->{ 'other' }->{ 'active_library' } });
        $request->store;

        # Send an email, if requested
        if ( $params->{ 'other' }->{ 'send_email' } && $params->{ 'other' }->{ 'send_email' } == 1 ) {
            my $email = {
                'message_transport_type' => 'email',
                'code' => $params->{ 'other' }->{ 'letter_code' },
                'title' => $params->{ 'other' }->{ 'email_title' },
                'content' => $params->{ 'other' }->{ 'email_content' },
            };
            C4::Message->enqueue($email, $patron->unblessed, 'email');
        }

        # Send an sms, if requested
        if ( $params->{ 'other' }->{ 'send_sms' } && $params->{ 'other' }->{ 'send_sms' } == 1 ) {
            my $sms = {
                'message_transport_type' => 'sms',
                'code' => $params->{ 'other' }->{ 'letter_code' },
                'title' => $params->{ 'other' }->{ 'sms_title' },
                'content' => $params->{ 'other' }->{ 'sms_content' },
            };
            C4::Message->enqueue($sms, $patron->unblessed, 'sms');
        }

        # Change the status of the request
        if ( $request->illrequestattributes->find({ type => 'media_type' })->value eq 'Lån' ) {

            ## This is a loan

            # Set the status to "arrived"
            $request->status( 'IN_ANK' );
            $request->store;

            # Save the two due dates
            if ( $params->{ 'other' }->{ 'due_date_guar' } ) {
                Koha::Illrequestattribute->new({
                    illrequest_id => $request->illrequest_id,
                    type          => 'due_date_guar',
                    value         => $params->{ 'other' }->{ 'due_date_guar' },
                })->store;
            }
            if ( $params->{ 'other' }->{ 'due_date_max' } ) {
                Koha::Illrequestattribute->new({
                    illrequest_id => $request->illrequest_id,
                    type          => 'due_date_max',
                    value         => $params->{ 'other' }->{ 'due_date_max' },
                })->store;
            }

            # Set a barcode, if one was supplied
            my $barcode = $params->{other}->{ill_barcode};
            if ( $barcode ) {
                my $item = Koha::Items->find({ 'biblionumber' => $request->biblio_id });
                if ( $item->barcode ) {
                    warn "Item already has barcode: " . $item->barcode;
                } else {
                    $item->barcode( $barcode );
                    $item->store;
                }
            }

        } else {

            ## This is an article/copy

            if ( $ill_config->{'close_article_request_on_receive'} && $ill_config->{'close_article_request_on_receive'} == 1 ) {
                # Mark the request as "done"
                $request->status( 'IN_AVSL' );
                $request->store;
                # Close the request (delete record and item, anonymize etc)
                $self->close($params);
            } else {
                # Mark the request as "received". It will have to be closed later.
                $request->status( 'IN_ANK' );
                $request->store;

            }

        }

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'receive',
            stage   => 'commit',
            next    => 'illview',
        };

    } else {

        ## Show the screen for receiving something

        my $item = Koha::Items->find({ biblionumber => $request->biblio_id });

        my $letter_code = 'ILL_ANK_LAN';
        if ( $request->illrequestattributes->find({type => 'media_type'}) && $request->illrequestattributes->find({type => 'media_type'})->value eq 'Kopia' ) {
            $letter_code = 'ILL_ANK_KOPIA';
        }

        # Prepare email
        my $email =  C4::Letters::GetPreparedLetter (
            module => 'circulation',
            letter_code => $letter_code,
            message_transport_type => 'email',
            branchcode => $patron->branchcode,
            lang => $patron->lang,
            tables => {
                'biblio', $item->biblionumber,
                'biblioitems', $item->biblionumber,
                'borrowers', $patron->borrowernumber,
            },
        );

        # Prepare SMS
        my $sms =  C4::Letters::GetPreparedLetter (
            module => 'circulation',
            letter_code => $letter_code,
            message_transport_type => 'sms',
            branchcode => $patron->branchcode,
            lang => $patron->lang,
            tables => {
                'biblio', $item->biblionumber,
                'biblioitems', $item->biblionumber,
                'borrowers', $patron->borrowernumber,
            },
        );

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'receive',
            stage   => 'form',
            next    => 'illview',
            illrequest_id => $request->illrequest_id,
            borrowernumber => $request->borrowernumber,
            title     => $request->illrequestattributes->find({ type => 'title' })->value,
            author    => $request->illrequestattributes->find({ type => 'author' })->value,
            lf_number => $request->illrequestattributes->find({ type => 'lf_number' })->value,
            type      => $request->illrequestattributes->find({ type => 'media_type' })->value,
            active_library => => $request->illrequestattributes->find({ type => 'active_library' })->value,
            letter_code => $letter_code,
            email     => $email,
            sms       => $sms,
            # value   => $request_details,
        };

    }

}

sub get_data_by_mode {

    my ( $ill_config, $mode, $query ) = @_;

    if ( $query ) {
        # Add leading questionmark
        $query = "?$query";
    } else {
        # Avoid error of uninitialized variable later
        $query = '';
    }

    return get_data( $ill_config, "illrequests/__sigil__/$mode$query" );

}

=head2 upsert_receiving_library()

Takes the sigil of a library as an argument and looks it up in the "libraries"
endpoint of the Libris API. If a library with that sigil already exists in the
Koha database, and the config variable B<update_library_data> is true, it is updated.
If it does not exist, a new library is inserted, based on the retrieved data.

The borrowernumber of the library in question is returned, either way.

=cut

sub upsert_receiving_library {

    my ( $ill_config, $receiver_sigil ) = @_;

    my $partner_code = $ill_config->{ 'partner_code' };
    my $ill_branch = $ill_config->{ 'ill_branch' };

    my $all_lib_data = get_data( $ill_config, "libraries/__sigil__/$receiver_sigil" );
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
        categorycode => $partner_code,
        branchcode   => $ill_branch,
        userid       => $receiver_sigil,
        password     => '!',
        address      => $lib_data->{'address1'},
        address2     => $address2,
        city         => $lib_data->{'city'},
        zipcode      => $lib_data->{'zip_code'},
    };

    if ( $library && $ill_config->{ 'update_library_data' } && $ill_config->{ 'update_library_data' } == 1 ) {
        # say "*** Updating existing library" if $verbose;
        $library->update( $new_library_data );
    } else {
        # say "*** Inserting new library" if $verbose;
        $library = Koha::Patron->new( $new_library_data )->store();
    }

    return $library;

}


sub upsert_record {

    my ( $ill_config, $action, $libris_req, $homebranch, $holdingbranch, $saved_req ) = @_;

    my $ill_itemtype   = $ill_config->{ 'ill_itemtype' };
    my $ill_callnumber = $ill_config->{ 'ill_callnumber' } ? $ill_config->{ 'ill_callnumber' } : '';
    my $ill_notforloan = defined($ill_config->{ 'ill_notforloan' }) ? $ill_config->{ 'ill_notforloan' } : 0;

    # Get the record
    my $record;
    if ( $libris_req->{ 'bib_id' } =~ m/^BIB/i ) { 
        # There is no Libris record identifier, bib_id = "BIB" + request_id. Create a mininal record
        $record = get_record_from_request( $libris_req );
    } else {
        # Looks like we have a Libris record ID, so get the record and save it
        #
        # But first, check if the Libris record ID is already present in the
        # database. There could be a good reason why the record is already there
        # and we have to create a new one. So if there is one record in the db
        # already, that is not considered a problem. But if there are "a lot"
        # of copies, this might indicate this script is failing somewhere between
        # importing and adding the record, and creating the ILL request in the
        # database. So we check for the number and bail out loudly if we are above
        # it.
        my $count_recordid = count_recordid( $libris_req->{ 'bib_id' } );
        say "Found $count_recordid occurrences of recordid=" . $libris_req->{ 'bib_id' };
        my $recordid_limit = 100; # Default
        if ( defined $ill_config->{ 'recordid_limit' } ) {
            # Use the limit from the config
            $recordid_limit = $ill_config->{ 'recordid_limit' };
        }
        if ( $count_recordid >= $recordid_limit ) {
            # Bail out if we are over the limit
            die "Too many copies of recordid=" . $libris_req->{ 'bib_id' };
        }
        # Now get the actual record
        $record = get_record_from_libris( $libris_req->{ 'bib_id' } );
    }

    # Make sure we have the default itemtype in 942$c
    $record->insert_fields_ordered(
        MARC::Field->new('942', '', '', c => $ill_itemtype ),
    );

    # Update or save the record
    my ( $biblionumber, $biblioitemnumber );
    if ( $action eq 'update' ) { 
        # Find the record connected to the saved request
        $biblionumber = $saved_req->biblio_id;
        # Update record
        ModBiblio( $record, $biblionumber, '' );
        say "Updated record with biblionumber=$biblionumber";
    } else {
        # Add a new record
        ( $biblionumber, $biblioitemnumber ) = AddBiblio( $record, '' );
        say "Added new record with biblionumber=$biblionumber";
        my $item_hash = {
            'biblionumber'   => $biblionumber,
            'biblioitemnumber' => $biblioitemnumber,
            'homebranch'     => $homebranch,
            'holdingbranch'  => $holdingbranch,
            'itype'          => $ill_itemtype,
            'itemcallnumber' => $ill_callnumber,
            'notforloan'     => $ill_notforloan
        };
        my $item = Koha::Item->new( $item_hash );
        if ( defined $item ) {
            $item->store;
            my $itemnumber = $item->itemnumber;
            say "Added new item with itemnumber=$itemnumber and notforloan: " . $item->notforloan;
        } else {
            say "No item added";
        }
    }

    return $biblionumber;
}

sub get_record_from_libris {

    my ( $libris_id ) = @_; 

    my $xml = get("http://api.libris.kb.se/sru/libris?version=1.1&operation=searchRetrieve&query=rec.recordIdentifier=$libris_id");
    return unless $xml;
    $xml =~ m/(<record .*>.*?<\/record>)<\/recordData>/;
    my $record_xml = $1;
    return unless $record_xml;
    my $record = MARC::Record->new_from_xml( $record_xml, 'UTF-8', 'MARC21' );
    return unless $record;

    $record->encoding( 'UTF-8' );

    # Remove unnecessary fields
    foreach my $tag ( qw( 841 852 887 950 955 ) ) {
       $record->delete_fields( $record->field( $tag ) );
    }

    say $record->as_xml();

    return $record;

}

sub get_record_from_request {

    my ( $req ) = @_; 

    # Create a new record
    my $record = MARC::Record->new();

    my $f001 = MARC::Field->new( '001', $req->{ 'bib_id' } );
    $record->insert_fields_ordered( $f001 );

    if ( $req->{ 'author' } && $req->{ 'author' } ne '' ) {
        my $author = MARC::Field->new(
            '100',' ',' ',
            a => $req->{ 'author' },
        );  
        $record->insert_fields_ordered( $author );
    }

    my $title = MARC::Field->new(
        '245',' ',' ',
        a => $req->{ 'title' },
    );
    $record->insert_fields_ordered( $title );

    # FIXME Add more fields, especially for articles

    say $record->as_xml();

    return $record;

}

sub get_request_data {

    my ( $ill_config, $orderid ) = @_;
    return get_data( $ill_config, "illrequests/__sigil__/$orderid" );

}

sub get_data {

    my ( $ill_config, $fragment ) = @_;

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
    say STDERR "Requesting $url";
    my $request = HTTP::Request->new( GET => $url );
    $request->header( 'api-key' => $libriskey );

    # Pass request to the user agent and get a response back
    my $res = $ua->request($request);

    my $json;
    # Check the outcome of the response
    if ($res->is_success) {
        $json = $res->content;
    } else {
        say STDERR $res->status_line;
    }

    unless ( $json ) {
        die "No JSON!\n";
    }

    my $data = decode_json( $json );
    if ( $data->{'count'} == 0 ) {
        die "No data!\n";
    }

    # say Dumper $data if $debug;

    return $data;

}

=head3 userid2borrower

  my $borrower = userid2borrower( $user_id );

Takes a user ID (found in user_id in the Libris API) and returns the
corresponding borrower, if one exists. If a patron is not found, the
unknown_patron from the ILL config will be returned.

By default, "cardnumber" is used as the user ID that is looked for. This can be
changed with the optional config variable "patron_id_field". Possible values for
this variable:

=over 4

=item * cardnumber (default)

=item * userid

=item * borrowernumber

=back

=cut

sub userid2borrower {

    my ( $user_id ) = @_;
    my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
    my $ill_config = LoadFile( $ill_config_file );

    # Make sure we have a user ID to look up
    chomp $user_id;
    return $ill_config->{ 'unknown_patron' } unless $user_id;
    return $ill_config->{ 'unknown_patron' } if $user_id eq '';

    # Look up the patron, based on cardnumber as default, or another identifier
    # specified in the ILL config
    my $id_field = 'cardnumber';
    if ( $ill_config->{ 'patron_id_field' } && $ill_config->{ 'patron_id_field' } ne '' ) {
        $id_field = $ill_config->{ 'patron_id_field' };
    }
    my $patron = Koha::Patrons->find({ $id_field => $user_id });

    # If we do not have a patron yet, and patron_id_attributes is set, use the
    # attributes to look for the patron.
    if ( !$patron && defined $ill_config->{ 'patron_id_attributes' } ) {

        my @cond;
        my @needles;
        # Build the WHERE part of the query
        foreach my $attr ( @{ $ill_config->{'patron_id_attributes'} } ) {
            push @cond, "(code = '$attr' AND attribute = ?)";
            push @needles, $user_id;
        }
        my $where = join( " OR ", @cond );

        # Execute the query
        my $query = "SELECT borrowernumber FROM borrower_attributes WHERE $where;";
        my $dbh = C4::Context->dbh;
        my $sth = $dbh->prepare($query);
        $sth->execute( @needles );
        my $borrowernumber = $sth->fetchrow_array;

        # Find the borrower
        if ( $borrowernumber ) {
            $patron = Koha::Patrons->find({ 'borrowernumber' => $borrowernumber });
        }

    }

    if ( $patron ) {
        return $patron;
    } else {
        return Koha::Patrons->find({ 'borrowernumber' => $ill_config->{ 'unknown_patron' } });
    }

}

=head3 recordid2biblionumber

  my $biblionumber = recordid2biblionumber( $recordid );

Takes a record ID (typically found in the 001 MARC field), checks if
it exists in the database and if it does, returns the corresponding
biblionumber.

This uses the ExtractValue function to search through all the MARC records in the
database for the 001 field from the incoming record. This can be a heavy burden
if the database holds a lot of records. See this Koha bug for a proposed
enhancement that could alleviate this situation:
L<https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=25603>

=cut

sub recordid2biblionumber {

    my ( $recordid ) = @_;

    my $dbh = C4::Context->dbh;
    my $hits = $dbh->selectrow_hashref( 'SELECT biblionumber FROM biblio_metadata WHERE ExtractValue( metadata,\'//controlfield[@tag="001"]\' ) = ?', undef, ( $recordid ) );
    my $biblionumber = $hits->{'biblionumber'};

    return $biblionumber;

}

=head3 count_recordid

  my $count = count_recordid( $recordid );

Takes a record ID (typically found in the 001 MARC field), and returns the
number of times it occurs in the database.

See above for notes on the use of ExtractValue.

=cut

sub count_recordid {

    my ( $recordid ) = @_;

    my $dbh = C4::Context->dbh;
    my $hits = $dbh->selectrow_hashref( 'SELECT COUNT(*) AS count FROM biblio_metadata WHERE ExtractValue( metadata,\'//controlfield[@tag="001"]\' ) = ?', undef, ( $recordid ) );
    my $count = $hits->{'count'};

    return $count;

}

=head3 set_status_read

Set the status of a request to "read" ("Läst").

=cut

sub set_status_read {

    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $res = _update_libris( $request, 'read' );

    # Check the outcome of the response
    if ( $res->is_success ) {

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => 'Status updated',
            method  => 'set_status_read',
            stage   => 'commit',
            next    => 'illview',
            # value   => $request_details,
        };

    } else {

        # -> create response.
        return {
            error   => 1,
            status  => '',
            message => $res->status_line,
            method  => 'set_status_read',
            stage   => 'error',
            next    => 'illview',
            # value   => $request_details,
        };

    }

}

=head3 respond

Set a selection of statuses.

=cut

sub respond {

    my ( $self, $params ) = @_; 
    my $stage = $params->{other}->{stage};
    my $request = $params->{request};
    # my $status = $request->status;
    # $status =~ m/(.*?_).*/g;
    # my $direction = $1;

    if ( $stage && $stage eq 'response' ) { 

        warn "Going to update request";
        # &response_id=2&added_response=Test&may_reserve=0
        my $response_id    = $params->{other}->{response_id};
        my $added_response = $params->{other}->{added_response};
        my $may_reserve    = $params->{other}->{may_reserve};
        my $extra_content  = "&response_id=$response_id&added_response=$added_response&may_reserve=$may_reserve";
        warn $extra_content;
        my $res = _update_libris( $request, 'response', $extra_content );

        if ( $res->is_success ) {

            # -> create response.
            return {
                error   => 0,
                status  => '', 
                message => '', 
                method  => 'respond',
                stage   => 'commit',
                next    => 'illview',
                # value   => $request_details,
            };

        } else {
        
            # -> create response.
            return {
                error   => 1,
                status  => '', 
                message => $res->status_line, 
                method  => 'respond',
                stage   => 'commit',
                next    => 'illview',
                # value   => $request_details,
            }; 

        }

    } else {

        # -> create response.
        return {
            error   => 0,
            status  => '', 
            message => '', 
            method  => 'respond',
            stage   => 'form',
            next    => 'illview',
            illrequest_id => $request->illrequest_id,
            title     => $request->illrequestattributes->find({ type => 'title' })->value,
            author    => $request->illrequestattributes->find({ type => 'author' })->value,
            lf_number => $request->illrequestattributes->find({ type => 'lf_number' })->value
            # value   => $request_details,
        };

    }   

}

sub _update_libris {

    my ( $request, $action, $extra_content ) = @_;

    my $orderid = $request->orderid;
    warn "*** orderid: $orderid";

    # Figure out the sigil that the current request is connected to
    my $sigil = $request->illrequestattributes->find({ type => 'requesting_library' })->value();
    warn "Handling request on behalf of $sigil";

    # Get the path to, and read in, the Libris ILL config file
    my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
    my $ill_config = LoadFile( $ill_config_file );

    # Make sure relevant data for the active sigil/library are easily available
    $ill_config->{ 'libris_sigil' } = $sigil;
    $ill_config->{ 'libris_key' } = $ill_config->{ 'libraries' }->{ $sigil }->{ 'libris_key' };

    my $status = $request->status;
    $status =~ m/(.*?)_.*/g;
    my $direction = $1;

    my $orig_data = _get_data_from_libris( $ill_config, "illrequests/$sigil/$orderid" );

    # Pick out the timestamp
    my $timestamp = $orig_data->{'ill_requests'}->[0]->{'last_modified'};
    warn "*** timestamp: $timestamp";

    ## Make the call back to Libris, to change the status

    # Create a user agent object
    my $ua = LWP::UserAgent->new;
    $ua->agent("Koha ILL");

    # Create a request
    my $url = "http://iller.libris.kb.se/librisfjarrlan/api/illrequests/$sigil/$orderid";
    warn "POSTing to $url";
    my $req = HTTP::Request->new( 'POST', $url );
    warn "*** libris_key: " . $ill_config->{'libris_key'};
    $req->header( 'api-key' => $ill_config->{'libris_key'} );
    $req->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
    $req->content( "action=$action&timestamp=$timestamp$extra_content" );

    # Pass request to the user agent and get a response back
    my $res = $ua->request($req);

    # Check the outcome of the response
    if ( $res->is_success ) { 

        my $json = $res->content;
        my $new_data = decode_json( $json );

        warn "*** Update action: " . $new_data->{'update_action'};
        warn "*** Update success: " . $new_data->{'update_success'};
        warn "*** Update message: " . $new_data->{'update_message'};
        warn "*** Last modified: " . $new_data->{'ill_requests'}->[0]->{'last_modified'};
        warn "*** Status: " . $new_data->{'ill_requests'}->[0]->{'status'};

        # Update the request in the database
        # FIXME Create a proper sub for updating data
        $request->status( $direction . '_' . translate_status( $new_data->{'ill_requests'}->[0]->{'status'} ) );
        $request->illrequestattributes->find({ type => 'last_modified' })->value( $new_data->{'ill_requests'}->[0]->{'last_modified'} );
        $request->store;

    } else {

        warn "--- ERROR ---";

    }

    return $res;

}

sub _get_data_from_libris {

    my ( $ill_config, $fragment ) = @_;

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
    warn "Requesting $url";
    my $request = HTTP::Request->new( GET => $url );
    $request->header( 'api-key' => $libriskey );

    # Pass request to the user agent and get a response back
    my $res = $ua->request($request);

    my $json;
    # Check the outcome of the response
    if ($res->is_success) {
        $json = $res->content;
    } else {
        warn $res->status_line;
    }

    unless ( $json ) {
        warn "No JSON!";
        exit;
    }

    my $data = decode_json( $json );
    if ( $data->{'count'} == 0 ) {
        warn "No data!";
        exit;
    }

    return $data;

}

=head3 create

=cut

sub create {

    # -> initial placement of the request for an ILL order
    my ( $self, $params ) = @_;

    my $ill_config_file = C4::Context->config('interlibrary_loans')->{'libris_config'};
    my $ill_config = LoadFile( $ill_config_file );

warn "In create";
warn Dumper $params;

    my $other = $params->{other};
    my $stage = $other->{stage};

    if ( $stage && $stage eq 'from_api' ) {

        my $request = $params->{request};
        $request->orderid(        $params->{other}->{orderid} );
        $request->borrowernumber( $params->{other}->{borrowernumber} );
        $request->biblio_id(      $other->{biblio_id} );
        $request->branchcode(     $params->{other}->{branchcode} );
        $request->status(         $params->{other}->{status} );
        $request->placed(         DateTime->now);
        $request->replied(        );
        $request->completed(      );
        $request->medium(         $params->{other}->{medium} );
        $request->accessurl(      );
        $request->cost(           );
        $request->notesopac(      );
        $request->notesstaff(     );
        $request->backend(        $params->{other}->{backend} );
        $request->store;
        # ...Populate Illrequestattributes
        while ( my ( $type, $value ) = each %{$params->{other}->{attr}} ) {
            Koha::Illrequestattribute->new({
                illrequest_id => $request->illrequest_id,
                type          => $type,
                value         => $value,
            })->store;
        }

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'create',
            stage   => 'commit',
            next    => 'illview',
            # value   => $request_details,
        };

    } elsif ( $stage && $stage eq 'save' ) {

        my $request = $params->{request};
        $request->orderid(        $params->{other}->{orderid} );
        $request->borrowernumber( $params->{other}->{borrowernumber} );
        $request->biblio_id(      $other->{biblio_id} );
        $request->branchcode(     $ill_config->{ 'ill_branch' } );
        $request->status(         'IN_UTEL' );
        $request->placed(         DateTime->now);
        $request->medium(         $params->{other}->{medium} );
        $request->accessurl(      $params->{other}->{accessurl} );
        $request->cost(           $params->{other}->{cost} );
        $request->notesopac(      $params->{other}->{notesopac} );
        $request->notesstaff(     $params->{other}->{notesstaff} );
        $request->backend(        'Libris' );
        $request->store;
        # ...Populate Illrequestattributes
        # Create a mapping between what the fields in the form are called and
        # what we want to save in the database. This also specifies which fields
        # should be saved as attributes.
        my %attrmap = (
            'medium'         => 'type',
            'illtitle'       => 'title',
            'author'         => 'author',
            'year'           => 'year',
            'isbn_issn'      => 'isbn_issn',
            'message'        => 'message',
            'active_library' => 'active_library',
            'medium'         => 'media_type',
            'due_date_guar'  => 'due_date_guar',
            'due_date_max'   => 'due_date_max',
            'volume'         => 'volume_designation',
            'volume'         => 'volume',
            'pages'          => 'pages',
            'arttitle'       => 'title_of_article',
            'arttitle'       => 'article_title',
            'artauthor'      => 'author_of_article',
            'year'           => 'year',
            'librarian'      => 'operator',
        );
        foreach my $type ( keys %attrmap ) {
            my $save_as_type = $attrmap{ $type };
            Koha::Illrequestattribute->new({
                illrequest_id => $request->illrequest_id,
                type          => $save_as_type,
                value         => $params->{other}->{ $type },
            })->store;
        }

# warn Dumper $params->{other}->{attr};

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'create',
            stage   => 'commit',
            next    => 'illview',
            # value   => $request_details,
        };

    } else {

        # Show the empty form

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'create',
            stage   => 'form',
            next    => 'save',
            # value   => $request_details,
        };

    }

}

=head3 confirm

  my $response = $backend->confirm({
      request    => $requestdetails,
      other      => $other,
  });

Confirm the placement of the previously "selected" request (by using the
'create' method).

In this case we will generally use $request.
This will be supplied at all times through Illrequest.  $other may be supplied
using templates.

=cut

sub confirm {

    my ( $self, $params ) = @_;
    my $stage = $params->{other}->{stage};

    if ( $stage && $stage eq 'response' ) {

        warn "Going to update request";
        # FIXME Do the actual update here

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'confirm',
            stage   => 'response',
            next    => 'illview',
            # value   => $request_details,
        };

    } else {

        # -> create response.
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'confirm',
            stage   => 'form',
            next    => 'illview',
            # value   => $request_details,
        };

    }

}

=head3 renew

  my $response = $backend->renew({
      request    => $requestdetails,
      other      => $other,
  });

Attempt to renew a request that was supplied through backend and is currently
in use by us.

We will generally use $request.  This will be supplied at all times through
Illrequest.  $other may be supplied using templates.

=cut

sub renew {
    # -> request a currently borrowed ILL be renewed in the backend
    my ( $self, $params ) = @_;
    # Turn Illrequestattributes into a plain hashref
    my $value = {};
    my $attributes = $params->{request}->illrequestattributes;
    foreach my $attr (@{$attributes->as_list}) {
        $value->{$attr->type} = $attr->value;
    };
    # Submit request to backend, parse response...
    my ( $error, $status, $message ) = ( 0, '', '' );
    if ( !$value->{status} || $value->{status} eq 'On order' ) {
        $error = 1;
        $status = 'not_renewed';
        $message = 'Order not yet delivered.';
    } else {
        $value->{status} = "Renewed";
    }
    # ...then return our result:
    return {
        error   => $error,
        status  => $status,
        message => $message,
        method  => 'renew',
        stage   => 'commit',
        value   => $value,
        next    => 'illview',
    };
}

=head3 cancel

  my $response = $backend->cancel({
      request    => $requestdetails,
      other      => $other,
  });

We will attempt to cancel a request that was confirmed.

We will generally use $request.  This will be supplied at all times through
Illrequest.  $other may be supplied using templates.

=cut

sub cancel {
    # -> request an already 'confirm'ed ILL order be cancelled
    my ( $self, $params ) = @_;
    # Turn Illrequestattributes into a plain hashref
    my $value = {};
    my $attributes = $params->{request}->illrequestattributes;
    foreach my $attr (@{$attributes->as_list}) {
        $value->{$attr->type} = $attr->value;
    };
    # Submit request to backend, parse response...
    my ( $error, $status, $message ) = (0, '', '');
    if ( !$value->{status} ) {
        ( $error, $status, $message ) = (
            1, 'unknown_request', 'Cannot cancel an unknown request.'
        );
    } else {
        $attributes->find({ type => "status" })->value('Reverted')->store;
        $params->{request}->status("REQREV");
        $params->{request}->cost(undef);
        $params->{request}->orderid(undef);
        $params->{request}->store;
    }
    return {
        error   => $error,
        status  => $status,
        message => $message,
        method  => 'cancel',
        stage   => 'commit',
        value   => $value,
        next    => 'illview',
    };
}

=head3 status

  my $response = $backend->create({
      request    => $requestdetails,
      other      => $other,
  });

We will try to retrieve the status of a specific request.

We will generally use $request.  This will be supplied at all times through
Illrequest.  $other may be supplied using templates.

=cut

sub status {
    # -> request the current status of a confirmed ILL order
    my ( $self, $params ) = @_;
    my $value = {};
    my $stage = $params->{other}->{stage};
    my ( $error, $status, $message ) = (0, '', '');
    if ( !$stage || $stage eq 'init' ) {
        # Generate status result
        # Turn Illrequestattributes into a plain hashref
        my $attributes = $params->{request}->illrequestattributes;
        foreach my $attr (@{$attributes->as_list}) {
            $value->{$attr->type} = $attr->value;
        }
        ;
        # Submit request to backend, parse response...
        if ( !$value->{status} ) {
            ( $error, $status, $message ) = (
                1, 'unknown_request', 'Cannot query status of an unknown request.'
            );
        }
        return {
            error   => $error,
            status  => $status,
            message => $message,
            method  => 'status',
            stage   => 'status',
            value   => $value,
        };

    } elsif ( $stage eq 'status') {
        # No more to do for method.  Return to illlist.
        return {
            error   => $error,
            status  => $status,
            message => $message,
            method  => 'status',
            stage   => 'commit',
            next    => 'illlist',
            value   => {},
        };

    } else {
        # Invalid stage, return error.
        return {
            error   => 1,
            status  => 'unknown_stage',
            message => '',
            method  => 'create',
            stage   => $params->{stage},
            value   => {},
        };
    }
}

=head1 AUTHOR

Magnus Enger <magnus@libriotech.no>

Based on the "Dummy" backend created by:
Alex Sassmannshausen <alex.sassmannshausen@ptfs-europe.com>

=cut

1;
