package On::Event;
# ABSTRACT: Flexible event handling over the power of AnyEvent
=pod

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

You can remove the has_event and has_events helpers by unimporting On::Event:

  no On::Event;

=cut
use strict;
use warnings;
use Any::Moose 'Role';

has 'autoload' => (isa=>'Bool', is=>'rw', default=>1);
has '_listeners' => (isa=>'HashRef', is=>'ro', default=>sub{{}});

sub import {
    my( $pkg ) = caller;
    foreach my $module ( @_[1..$#_] ) {
        my $class = "On::Event::$module"; ;
        eval qq{ package $pkg; use $class; };
        die $@ if $@;
    }
    no strict 'refs';
    *{$pkg."::has_event"} = \&has_event;
    *{$pkg."::has_events"} = \&has_event;
    *{$pkg."::_valid_events"} = {};
}

=begin internal

=over

=item our sub unimport

This is used to clean up the functions we insert into the caller's namespace.

=back

=end internal

=cut

sub unimport {
    my( $pkg ) = caller;
    no strict 'refs';
    delete ${$pkg."::"}{"has_event"};
    delete ${$pkg."::"}{"has_events"};
}

=head1 HELPERS (exported subroutines)

=over

=item sub has_event( Array[Str] *@event_names ) is export

=item sub has_events( Array[Str] *@event_names ) is export

=over

Registers your class as being able to trigger the event names listed.

=back

=back

=cut

sub has_event(@) {
    my( $pkg ) = caller;
    no strict 'refs';
    my $valid = \%{$pkg."::_valid_events"};
    $valid->{$_}=1 for @_;
}

=head1 METHODS

=over

=item our method event_exists( Str $event ) returns Bool

=over

Returns true if $event is a valid event name for this class.

=back

=cut

sub event_exists {
    my $self = shift;
    my( $event ) = @_;
    no strict 'refs';
    return exists ${ref($self)."::_valid_events"}{$event};
}

=pod

=item our method on( Str $event, Code $listener ) returns Code

=over

Registers $listener as a listener on $event.  When $event is triggered ALL
registered listeners are executed.

Returns the listener coderef.

=back

=cut

sub on {
    my $self = shift;
    my( $event, $listener ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->{_listeners}{$event} //= [];
    push @{ $self->{_listeners}{$event} }, $listener;
    return $listener;
}

=pod

=item our method trigger( Str $event, Array[Any] *@args )

=over

Normally called within the class using the On::Event role.  This calls all
of the registered listeners on $event with @args.

If you're using coroutines then each listener will get its own thread and
trigger will cede before returning.

=back

=cut

sub trigger {
    no warnings 'redefine';
    if ( defined *Coro::async{CODE} ) {
        *trigger = \&trigger_coro;
        goto \&trigger_coro;
    }
    else {
        *trigger = \&trigger_stock;
        goto \&trigger_stock;
    }
}

=begin internal

=item my method trigger_stock( Str $event, Array[Any] *@args )

=over

The standard impelementation of the trigger method-- calls the listeners
immediately and in the order they were defined.

=back

=end internal

=cut

sub trigger_stock {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_listeners}{$event};
    foreach ( @{ $self->{_listeners}{$event} } ) {
        $_->(@args);
    }
    return;
}

=begin internal

=item my method trigger_coro( Str $event, Array[Any] *@args )

=over

The L<Coro> implementation of the trigger method-- calls each of the listeners
in its own thread and triggers immediate execution by calling cede before
returning.

=back

=end internal

=cut

sub trigger_coro {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_listeners}{$event};
    foreach ( @{ $self->{_listeners}{$event} } ) {
        &Coro::async( $_, @args );
    }
    Coro::cede();
    return;
}

=pod

=item our method remove_all_listeners( Str $event )

=over

Removes all listeners for $event

=back

=back

=cut


sub remove_all_listeners {
    my $self = shift;
    my( $event ) = @_;
    delete $self->{_listeners}{$event};
}

no Any::Moose;
1;
