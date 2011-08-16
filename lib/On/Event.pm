=pod

=head1 NAME

On::Event -- Flexible event handling over the power of AnyEvent

=head1 SYNOPSIS

  package Example;
  use Any::Moose;
  use On::Event;
  with 'On::Event';
  has_event 'ping';
  
  package main;
  my $example = Example->new;
  $example->on( ping => sub { say "Got a ping!" } );
  $example->on( ping => sub { say "Got another ping!" } );
  $example->trigger( "ping" ); # prints "Got a ping!" and "Got another ping!"
  $example->remove_all_listeners( 'ping' );

=head1 DESCRIPTION

This provides a simple and flexible event API, implemented on top of
AnyEvent.  The API is in the style of Node.js.

=head1 USING

On::Event is implemented as a Moose Role.  To add events to your object:

  with 'On::Event';

It provides a helper declare what events your object supports:

  use On::Event;
  
  has_event 'event_name';
  has_events qw( event1 event2 event3 );

Users of your class can now call the "on" method in order to register an event handler:

  $obj->on( event1 => sub { say "I has an event;" } );

And clear their event listeners with:

  $obj->remove_all_listeners( 'ping' );

You can trigger events from your class with the "trigger" method:

  $self->trigger( "event1", "arg1", "arg2", "argn" );

=cut
package On::Event;
use strict;
use warnings;
use Any::Moose 'Role';

has 'autoload' => (isa=>'Bool', is=>'rw', default=>1);
has '_events' => (isa=>'HashRef', is=>'ro', default=>sub{{}});

sub import {
    my( $pkg ) = caller;
    foreach my $module ( @_[1..$#_] ) {
        my $class = "On::Event::$module"; ;
        eval qq{ use $class; };
        die $@ if $@;
    }
    no strict 'refs';
    *{$pkg."::has_event"} = \&has_event;
    *{$pkg."::has_events"} = \&has_event;
    *{$pkg."::_valid_events"} = {};
}

sub unimport {
    my( $pkg ) = caller;
    delete ${$pkg."::"}{"has_event"};
    delete ${$pkg."::"}{"has_events"};
}

=head1 HELPERS

sub has_event( Array[Str] @event_names )

sub has_events( Array[Str] @event_names )

=over

Registers your class as being able to trigger the event names listed.

=back

=cut

sub has_event(@) {
    my( $pkg ) = caller;
    no strict 'refs';
    my $valid = \%{$pkg."::_valid_events"};
    $valid->{$_}=1 for @_;
}

=head1 METHODS

method event_exists( Str $event ) returns Bool

=over



=back

=cut

sub event_exists {
    my $self = shift;
    my( $event ) = @_;
    no strict 'refs';
    return exists ${ref($self)."::_valid_events"}{$event};
}

sub on {
    my $self = shift;
    my( $event, $action ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->{_events}{$event} //= [];
    push @{ $self->{_events}{$event} }, $action;
}

sub trigger {
    no strict 'refs';
    no warnings;
    if ( defined *{"Coro::async"}{CODE} ) {
        *{trigger} = \&trigger_coro;
        goto \&trigger_coro;
    }
    else {
        *{trigger} = \&trigger_stock;
        goto \&trigger_stock;
    }
}

sub trigger_stock {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_events}{$event};
    foreach ( @{ $self->{_events}{$event} } ) {
        $_->(@args);
    }
    return;
}

sub trigger_coro {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_events}{$event};
    foreach ( @{ $self->{_events}{$event} } ) {
        &Coro::async( $_, @args );
    }
    Coro::cede();
    return;
}

sub remove_all_listeners {
    my $self = shift;
    my( $event ) = @_;
    delete $self->{_events}{$event};
}


no Any::Moose;
1;

