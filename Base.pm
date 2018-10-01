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
use Koha::Illrequestattribute;
use Koha::Patrons;
use utf8;

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
    $return->{'Libris best.nr'}
        = $attrs->find({type => 'lf_number'})
        ? $attrs->find({type => 'lf_number'})->value
        : '';
    $return->{'Typ'}
        = $attrs->find({type => 'media_type'})
        ? $attrs->find({type => 'media_type'})->value
        : '';
    $return->{'År'}
        = $attrs->find({type => 'year'})
        ? $attrs->find({type => 'year'})->value
        : '';

    return $return;
}

=head3 status_graph

=cut

sub status_graph {
    return {

        Remitterad => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Remitterad',                   # ID of this status
            name           => 'Remitterad',                   # UI name of this status
            ui_method_name => 'Remitterad',                   # UI name of method leading
                                                           # to this status
            method         => 'create',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-plus',                   # UI Style class
        },
        Uteliggande => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Uteliggande',                   # ID of this status
            name           => 'Uteliggande',                   # UI name of this status
            ui_method_name => 'Uteliggande',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        Levererad => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Levererad',                   # ID of this status
            name           => 'Levererad',                   # UI name of this status
            ui_method_name => 'Levererad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "Läst" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Läst',                   # ID of this status
            name           => 'Läst',                   # UI name of this status
            ui_method_name => 'Läst',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "Kan reserveras" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Kan reserveras',                   # ID of this status
            name           => 'Kan reserveras',                   # UI name of this status
            ui_method_name => 'Kan reserveras',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "Makulerad" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Makulerad',                   # ID of this status
            name           => 'Makulerad',                   # UI name of this status
            ui_method_name => 'Makulerad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "Negativt svar" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Negativt svar',                   # ID of this status
            name           => 'Negativt svar',                   # UI name of this status
            ui_method_name => 'Negativt svar',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "Reservation" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Reservation',                   # ID of this status
            name           => 'Reservation',                   # UI name of this status
            ui_method_name => 'Reservation',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },
        "Reserverad" => {
            prev_actions => [ ],                           # Actions containing buttons
                                                           # leading to this status
            id             => 'Reserverad',                   # ID of this status
            name           => 'Reserverad',                   # UI name of this status
            ui_method_name => 'Reserverad',                   # UI name of method leading
                                                           # to this status
            method         => 'requestitem',                    # method to this status
            next_actions   => [ 'KILL' ], # buttons to add to all
                                                           # requests with this status
            ui_method_icon => 'fa-send-o',                   # UI Style class
        },

    };
}

=head3 create

New Libris requests are always created/initiated in Libris itself,
so this is just a dummy method, because the ILL module expects there
to be a create subroutine.

=cut

sub create {

    # -> initial placement of the request for an ILL order
    my ( $self, $params ) = @_;

    # -> create response.
    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'create',
        stage   => 'msg',
        next    => 'illview',
        # value   => $request_details,
    };

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
    # -> confirm placement of the ILL order
    my ( $self, $params ) = @_;
    # Turn Illrequestattributes into a plain hashref
    my $value = {};
    my $attributes = $params->{request}->illrequestattributes;
    foreach my $attr (@{$attributes->as_list}) {
        $value->{$attr->type} = $attr->value;
    };
    # Submit request to backend...

    # No-op for Dummy

    # ...parse response...
    $attributes->find({ type => "status" })->value('On order')->store;
    my $request = $params->{request};
    $request->cost("30 GBP");
    $request->orderid($value->{id});
    $request->status("REQ");
    $request->accessurl("URL") if $value->{url};
    $request->store;
    $value->{status} = "On order";
    $value->{cost} = "30 GBP";
    # ...then return our result:
    return {
        error    => 0,
        status   => '',
        message  => '',
        method   => 'confirm',
        stage    => 'commit',
        next     => 'illview',
        value    => $value,
    };
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
