package ONE;
# Dist::Zilla: +PodWeaver
# ABSTRACT: A Node style event Role for Moose
=head1 SYNOPSIS

  package Example;
  use ONE;
  has_event 'pinged';
  sub ping {
      my $self = shift;
      $self->emit('pinged');
  }
  
  package main;
  my $example = Example->new;
  $example->on( pinged => sub { say "Got a ping!" } );
  $example->on( pinged => sub { say "Got another ping!" } );
  $example->ping; # prints "Got a ping!" and "Got another ping!"
  $example->remove_all_listeners( "pinged" ); # Remove all of the pinged listeners
  $example->once( pinged => sub { say "First ping." } );
  $example->ping; $example->ping; # Only prints "First ping." once
  my $listener = $example->on( pinged => sub { say "Ping" } );
  $example->remove_listener( pinged => $listener );
  $example->ping(); # Does nothing

=for test_synopsis
use v5.10;

=head1 OVERVIEW

This provides Node.js style events in a Role for Moose.

ONE is implemented as a Moose Role.  To add events to your object:

  use 'ONE';

It provides a helper declare what events your object supports:
  
  has_event 'event';
  ## or
  has_events qw( event1 event2 event3 );

Users of your class can now call the "on" method in order to register an event handler:

  $obj->on( event1 => sub { say "I has an event"; } );

And clear their event listeners with:

  $obj->remove_all_listeners( "event1" );

Or add and clear just one listener:

  my $listener = $obj->on( event1 => sub { say "Event here"; } );
  $obj->remove_listener( event1 => $listener );

You can trigger events from your class with the "emit" method:

  $self->emit( event1 => ( "arg1", "arg2", "argn" ) );

You can remove the has_event and has_events helpers by unimporting ONE:

  no ONE;

=cut

use strict;
use warnings;
use Any::Moose 'Role';
use Any::Moose '::Exporter';

has '_listeners'    => (isa=>'HashRef', is=>'ro', default=>sub{ {} });

my %valid_events;
has '_valid_events' => (isa=>'HashRef', is=>'ro', default=>sub{ $valid_events{ref $_[0]} ||= {} });

=event new_listener( Str $event, CodeRef $listener )

Called when a listener is added.  $event is the name of the event being listened to, and $listener is the
listener being installed.

=cut

&has_event('new_listener');

{
    my ($import, $unimport, $init_meta) = any_moose('::Exporter')->build_import_methods(
        as_is => [ 'has_event', 'has_events' ],
        also  => [ any_moose() ] );

    *unimport = $unimport;
    *init_meta = $init_meta if defined $init_meta;

    sub import {
        my $class = shift;
        my $caller = caller();
        $class->$import( { into => $caller }, @_ );
        eval "package $caller; with('ONE');";
    }
}


=head1 HELPERS (exported subroutines)

=head2 sub has_event( Array[Str] *@event_names ) is export

=head2 sub has_events( Array[Str] *@event_names ) is export

Registers your class as being able to emit the event names listed.

=cut

sub has_event(@) { ## no critic (ProhibitSubroutinePrototypes)
    my( $pkg ) = caller;
    $valid_events{$pkg}{$_} = 1 for @_;
}

## Create the has_events alias
BEGIN { *has_events = \&has_event; }

=method our method event_exists( Str $event ) returns Bool

Returns true if $event is a valid event name for this class.

=cut

sub event_exists {
    # If we have it in our list of valid events, do as little as possible
    # and return immediately...
    return 1 if exists $_[0]->{'_valid_events'}{$_[1]};
    
    # Otherwise we have to dig through all the roles attached to this object
    # and all of it's ancestors.
    my $self = shift;
    my( $event ) = @_;
    
    # Scan all of the roles this object has to see if they declare this event...
    for ( $self->meta->calculate_all_roles ) {
        if (exists $valid_events{$_->name}{$event}) {
            return $self->{'_valid_events'}{$event} = 1;
        }
    }
    
    # Scan all of the super classes of this object to see if they declare this event...
    for ( $self->meta->linearized_isa ) {
        if (exists $valid_events{$_}{$event}) {
            return $self->{'_valid_events'}{$event} = 1;
        }
    }
    
    # Otherwise, no, it doesn't exist
    return 0;
}

=method our method on( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event.  When $event is emitted ALL
registered listeners are executed.

Returns the listener coderef.

=cut

sub on {
    my $self = shift;
    my( $event, $listener ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->{_listeners}{$event} ||= [];
    $self->emit('new_listener', $event, $listener);
    push @{ $self->{_listeners}{$event} }, $listener;
    return $listener;
}

=method our method once( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event. Event listeners registered via
once will emit only once.

Returns the listener coderef.

=cut

sub once {
    my $self = shift;
    my( $event, $listener ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->{_listeners}{$event} ||= [];
    my $wrapped;
    $wrapped = sub { $_[0]->remove_listener($event=>$wrapped); $wrapped=undef; goto $listener; };
    $self->emit('new_listener', $event, $wrapped);
    push @{ $self->{_listeners}{$event} }, $wrapped;
    return $wrapped;
}

=method our method emit( Str $event, Array[Any] *@args )

Normally called within the class using the ONE role.  This calls all
of the registered listeners on $event with @args.

If you're using coroutines then each listener will get its own thread and
emit will cede before returning.

=cut

sub emit {
    no warnings 'redefine';
    if ( defined *Coro::async{CODE} ) {
        *emit = \&emit_coro;
        goto \&emit_coro;
    }
    else {
        *emit = \&emit_stock;
        goto \&emit_stock;
    }
}

=begin internal

=method my method emit_stock( Str $event, Array[Any] *@args )

The standard impelementation of the emit method-- calls the listeners
immediately and in the order they were defined.

=end internal

=cut

sub emit_stock {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_listeners}{$event};
    foreach ( @{ $self->{_listeners}{$event} } ) {
        $_->($self,@args);
    }
    return;
}

=begin internal

=method my method emit_coro( Str $event, Array[Any] *@args )

The L<Coro> implementation of the emit method-- calls each of the listeners
in its own thread and emits immediate execution by calling cede before
returning.

=end internal

=cut

sub emit_coro {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_listeners}{$event};
    foreach ( @{ $self->{_listeners}{$event} } ) {
        &Coro::async( $_, $self, @args );
    }
    Coro::cede();
    return;
}


=method our method remove_all_listeners( Str $event )

Removes all listeners for $event

=cut

sub remove_all_listeners {
    my $self = shift;
    if ( @_ ) {
        my( $event ) = @_;
        delete $self->{_listeners}{$event};
    }
    else {
        $self->{_listeners} = {};
    }
}

=method our method remove_listener( Str $event, CodeRef $listener )

Removes $listener from $event

=cut

sub remove_listener {
    my $self = shift;
    my( $event, $listener ) = @_;
    return unless exists $self->{_listeners}{$event};
    $self->{_listeners}{$event} =
        [ grep { $_ != $listener } @{ $self->{_listeners}{$event} } ];
}

=method our method listeners( Str $event ) returns ArrayRef[CodeRef]

For a given event, returns an arrayref of listener coderefs.  Editing this
list will edit the listeners for this item.

=cut

sub listeners {
    my $self = shift;
    my( $event ) = @_;
    return $self->{_listeners}{$event} ||= [];
}


=head1 SEE ALSO

Object::Event
Mixin::Event::Dispatch
Class::Publisher
Event::Notify
Notification::Center
Class::Observable
Reflex::Role::Reactive
Aspect::Library::Listenable
http://nodejs.org/docs/v0.5.4/api/events.html

=cut


no Any::Moose;
1;

