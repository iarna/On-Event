package On::Event;
# ABSTRACT: Flexible event handling built on the power of AnyEvent
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
  $example->emit( "ping" ); # prints "Got a ping!" and "Got another ping!"
  $example->remove_all_listeners( 'ping' );

=for test_synopsis
use v5.10;

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

You can trigger events from your class with the "emit" method:

  $self->emit( "event1", "arg1", "arg2", "argn" );

You can remove the has_event and has_events helpers by unimporting On::Event:

  no On::Event;

=cut

use strict;
use warnings;
use Any::Moose 'Role';
use Any::Moose '::Exporter';

has 'autoload'      => (isa=>'Bool',    is=>'rw', default=>1);
has '_listeners'    => (isa=>'HashRef', is=>'ro', default=>sub{ {} });

my %valid_events;
has '_valid_events' => (isa=>'HashRef', is=>'ro', default=>sub{ $valid_events{ref $_[0]} ||= {} });

sub has_event(@);
has_event 'new_listener';

my( $import, $unimport, $init_meta ) = any_moose('::Exporter')->build_import_methods(
    as_is => [ 'has_event' ] );

*unimport = $unimport;
*init_meta = $init_meta if defined $init_meta;


sub import {
    my( $pkg ) = caller;
    if ( @_ > 1 ) {
        for ( @_[1..$#_] ) {
            my( $class, $import_str ) = split /=/;
            my @imports = do { split( /\s*,\s*/, $import_str ) if defined $import_str };
            eval qq{ require On::Event::$class; }; ## no critic (ProhibitStringyEval)
            Carp::croak $@ if $@;
            eval qq{ package $pkg; On::Event::$class->import(\@imports); };## no critic (ProhibitStringyEval)
            Carp::croak $@ if $@;
        }
    }
    else {
        goto $import;
    }
}

=head1 HELPERS (exported subroutines)

=over

=item sub has_event( Array[Str] *@event_names ) is export

=item sub has_events( Array[Str] *@event_names ) is export

Registers your class as being able to emit the event names listed.

=back

=cut

sub has_event(@) { ## no critic (ProhibitSubroutinePrototypes)
    my( $pkg ) = caller;
    $valid_events{$pkg}{$_} = 1 for @_;
}

=head1 METHODS

=over

=item our method event_exists( Str $event ) returns Bool

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

=item our method on( Str $event, CodeRef $listener ) returns CodeRef

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

=item our method once( Str $event, CodeRef $listener ) returns CodeRef

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

=item our method emit( Str $event, Array[Any] *@args )

Normally called within the class using the On::Event role.  This calls all
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

=item my method emit_stock( Str $event, Array[Any] *@args )

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

=item my method emit_coro( Str $event, Array[Any] *@args )

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


=item our method remove_all_listeners( Str $event )

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

=item our method remove_listener( Str $event, CodeRef $listener )

Removes $listener from $event

=cut

sub remove_listener {
    my $self = shift;
    my( $event, $listener ) = @_;
    return unless exists $self->{_listeners}{$event};
    $self->{_listeners}{$event} =
        [ grep { $_ != $listener } @{ $self->{_listeners}{$event} } ];
}

=item our method listeners( Str $event ) returns ArrayRef[CodeRef]

For a given event, returns an arrayref of listener coderefs.  Editing this
list will edit the listeners for this item.

=cut

sub listeners {
    my $self = shift;
    my( $event ) = @_;
    return $self->{_listeners}{$event} ||= [];
}


=back

=head1 WHAT THIS ISN'T

This isn't an event loop, where one is needed, AnyEvent is used.  The core
module in this distribution isn't tied to any event loop at all.

=head1 JUSTIFICATION

While AnyEvent is a great event loop, it doesn't provide a standard mechnism
for making and triggering your own events.  This has resulted in everyone
doing their own thing, usually in the style of L<Object::Event>.  In find
the API and the limitations of this style (only one listener per event)
vexxing.  As such, this is my attempt at correcting the situation.

This is implemented as a Moose Role, so you can borrow event listening
functionality for any class.  It's implemented using Any::Moose, so if Moose
is too heavy weight for you, you can just use Mouse.

The core API is borrowed from the well thought out one in Node.js.  The
bundled modules generally follow Node's lead unless there's a good reason
not to.  For instance, the timer class does not, as Node implements them as
global functions.

=head1 SEE ALSO

=over

=item * L<Object::Event>

=item * L<Mixin::Event::Dispatch>

=item * L<Class::Publisher>

=item * L<Event::Notify>

=item * L<Notification::Center>

=item * L<Class::Observable>

=item * L<Reflex::Role::Reactive>

=item * L<http://nodejs.org/docs/v0.5.4/api/events.html>

=back

=cut


no Any::Moose;
1;

=for internal

=over

=item sub unimport

=back

=cut
