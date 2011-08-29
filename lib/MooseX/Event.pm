# ABSTRACT: A Node style event Role for Moose
# Dist::Zilla: +PodWeaver
package MooseX::Event;

use strict;
use warnings;
use namespace::autoclean;
use Any::Moose '::Exporter';
use Any::Moose '::Util';
use Scalar::Util qw( refaddr );
use Any::Moose 'Role';

has '_listeners'    => (isa=>'HashRef', is=>'ro', default=>sub{ {} });

my %valid_events;
has '_valid_events' => (isa=>'HashRef', is=>'ro', default=>sub{ $valid_events{ref $_[0]} ||= {} });


=attribute our Str $.current_event is rw

This is the name of the current event being triggered, or undef if no event
is being triggered.

=cut

has 'current_event' => (isa=>'Str|Undef', is=>'rw');

=event new_listener( Str $event, CodeRef $listener )

Called when a listener is added.  $event is the name of the event being listened to, and $listener is the
listener being installed.

=cut

&has_event('new_listener');


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

our @listener_wrappers;

=classmethod our method add_listener_wrapper( CodeRef $wrapper ) returns CodeRef

Wrappers are called in reverse declaration order.  They take a the listener
to be added as an argument, and return a wrapped listener.

=cut

sub add_listener_wrapper {
    my $class = shift;
    my( $wrapper ) = @_;
    push @listener_wrappers, $wrapper;
    return $wrapper;
}

=classmethod our method remove_listener_wrapper( CodeRef $wrapper )

Removes a previously added listener wrapper.

=cut

sub remove_listener_wrapper {
    my $class = shift;
    my( $wrapper ) = @_;
    @listener_wrappers = grep { $_ != $wrapper } @listener_wrappers;
}

=method our method on( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event.  When $event is emitted ALL
registered listeners are executed.

Returns the listener coderef.

=cut

sub on {
    my $self = shift;
    my( $event, $listener, @wrappers ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->{_listeners}{$event} ||= [];
    $self->{_aliases}{$event} ||= {};
    if ( ! @{$self->{_listeners}{$event}} and $self->can('activate_event') ) {
        $self->activate_event($event);
    }
    my @aliases;
    my $wrapped = $listener;
    for ( reverse(@wrappers), reverse(@listener_wrappers) ) {
        push @aliases, refaddr $wrapped;
        $wrapped = $_->( $wrapped );
    }
    $self->{_aliases}{$event}{refaddr $wrapped} = \@aliases;
    for ( @aliases ) {
        $self->{_aliases}{$event}{$_} = $wrapped;
    }
    $self->emit('new_listener', $event, $wrapped);
    push @{ $self->{_listeners}{$event} }, $wrapped;
    return $wrapped;
}

=method our method once( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event. Event listeners registered via
once will emit only once.

Returns the listener coderef.

=cut

sub once {
    my $self = shift;
    $self->on( @_, sub {
        my($listener) = @_;
        my $wrapped;
        $wrapped = sub {
            my $self = shift;
            $self->remove_listener($self->current_event=>$wrapped);
            $wrapped=undef;
            goto $listener;
        };
        return $wrapped;
    });
}

BEGIN {

=begin internal

=method my method emit_stock( Str $event, Array[Any] *@args )

The standard impelementation of the emit method-- calls the listeners
immediately and in the order they were defined.

=end internal

=cut

    my $emit_stock = sub {
        my $self = shift;
        my( $event, @args ) = @_;
        if ( ! $self->event_exists($event) ) {
            die "Event $event does not exist";
        }
        return unless exists $self->{_listeners}{$event};
        my $ce = $self->current_event;
        $self->current_event( $event );
        foreach ( @{ $self->{_listeners}{$event} } ) {
            $_->($self,@args);
        }
        $self->current_event($ce);
        return;
    };

=begin internal

=method my method emit_coro( Str $event, Array[Any] *@args )

The L<Coro> implementation of the emit method-- calls each of the listeners
in its own thread and emits immediate execution by calling cede before
returning.

=end internal

=cut

    my $emit_coro = sub {
        my $self = shift;
        my( $event, @args ) = @_;
        if ( ! $self->event_exists($event) ) {
            die "Event $event does not exist";
        }
        return unless exists $self->{_listeners}{$event};

        my $ce;
        foreach my $todo ( @{ $self->{_listeners}{$event} } ) {
            &Coro::async( sub {
                &Coro::on_enter( sub {
                    $ce  = $self->current_event;
                    $self->current_event($event);
                });
                $todo->(@_);
                &Coro::on_leave( sub {
                    $self->current_event($ce);
                });
            }, $self, @args );
        }
        Coro::cede();

        $self->current_event($ce);
        return;
    };

=method our method emit( Str $event, Array[Any] *@args )

Normally called within the class using the MooseX::Event role.  This calls all
of the registered listeners on $event with @args.

If you're using coroutines then each listener will get its own thread and
emit will cede before returning.

=cut

    sub emit {
        no warnings 'redefine';
        if ( defined *Coro::async{CODE} ) {
            *emit = $emit_coro;
            goto $emit_coro;
        }
        else {
            *emit = $emit_stock;
            goto $emit_stock;
        }
    }

}

=method our method remove_all_listeners( Str $event )

Removes all listeners for $event

=cut

sub remove_all_listeners {
    my $self = shift;
    if ( @_ ) {
        my( $event ) = @_;
        delete $self->{_listeners}{$event};
        delete $self->{_aliases}{$event};
        if ( $self->can('deactivate_event') ) {
            $self->deactivate_event($event);
        }
    }
    else {
        if ( $self->can('deactivate_event') ) {
            for ( keys %{$self->{_listeners}} ) {
                $self->deactivate_event($_);
            }
        }
        $self->{_listeners} = {};
        $self->{_aliases} = {};
    }
}

=method our method remove_listener( Str $event, CodeRef $listener )

Removes $listener from $event

=cut

sub remove_listener {
    my $self = shift;
    my( $event, $listener ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_listeners}{$event};
    
    my $aliases = $self->{_aliases}{$event}{refaddr $listener};
    delete $self->{_aliases}{$event}{refaddr $listener};
    
    if ( ref $aliases eq "ARRAY" ) {
        for ( @$aliases ) {
            delete $self->{_aliases}{$event}{$_};
        }
    }
    else {
        $listener = $aliases;
    }

    $self->{_listeners}{$event} =
        [ grep { $_ != $listener } @{ $self->{_listeners}{$event} } ];
        
    if ( ! @{$self->{_listeners}{$event}} and $self->can('deactivate_event') ) {
        $self->deactivate_event($event);
    }
}

BEGIN {
    my ($import, $unimport, $init_meta) = any_moose('::Exporter')->build_import_methods(
        as_is => [ 'has_event', 'has_events' ],
        also  => [ any_moose() ] );

    *init_meta = $init_meta if defined $init_meta;

    # We wrap the default import in order to load ourselves as a Role, without also
    # pulling in the import/unimport/init_meta methods.
    # Having import/unimport/init_meta as a Role is unusual, but we want them to
    # provide the has_event / has_events helpers. 
    sub import {
        my $class = shift;
        my $caller = caller();

        my $with_args = {-excludes=>[]};

        my @args;
        while (local $_ = shift @_) {
            if ( $_ eq '-alias' ) {
                $with_args->{'-alias'} = shift;
            }
            elsif ( $_ eq '-excludes' ) {
                my $excludes = shift;
                $with_args->{'-excludes'} = 
                    (ref $excludes eq 'ARRAY') ? $excludes: [$excludes];
            }
            else {
                push @args, $_;
            }
        }

        $class->$import( { into => $caller }, @args );

        push @{$with_args->{'-excludes'}}, qw( import unimport init_meta refaddr any_moose has_event has_events );
        
        if ( ! any_moose('::Util')->can('does_role')->( $caller, $class ) ) {
            $class->meta->apply( $caller->meta, %{$with_args} );
        }
    }
    
    sub unimport {
        my $class = shift;
        my $caller = caller;
        ## This doesn't seem to actually clean things up in Moose =/
        ## Where as it does just fine in Mouse
        $class->$unimport( { into => $caller }, @_ );
        my $syms = do { no strict 'refs'; \%{$caller.'::'} };
        for (qw( has_event has_events has before after around with override augment inner extends blessed carp )) {
            delete $syms->{$_};
        }
    }
}

no Any::Moose '::Role';

1;

=pod

=head1 SYNOPSIS

  package Example;
  use common::sense;
  use MooseX::Event;
  
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

=head1 DESCRIPTION

This provides Node.js style events in a Role for Moose.

MooseX::Event is implemented as a Moose Role.  To add events to your object:

  use MooseX::Event;

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

You can remove the has_event and has_events helpers by unimporting MooseX::Event

  no MooseX::event;

=head1 RELATED

=over

=item L<Object::Event>
=item L<Mixin::Event::Dispatch>
=item L<Class::Publisher>
=item L<Event::Notify>
=item L<Notification::Center>
=item L<Class::Observable>
=item L<Reflex::Role::Reactive>
=item L<Aspect::Library::Listenable>
=item L<http://nodejs.org/docs/v0.5.4/api/events.html>

=back
