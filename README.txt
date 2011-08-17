NAME
    On::Event - Flexible event handling over the power of AnyEvent

VERSION
    version v0.1.0

SYNOPSIS
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

DESCRIPTION
    This provides a simple and flexible event API, implemented on top of
    AnyEvent. The API is in the style of Node.js.

USING
    On::Event is implemented as a Moose Role. To add events to your object:

      with 'On::Event';

    It provides a helper declare what events your object supports:

      use On::Event;
  
      has_event 'event_name';
      has_events qw( event1 event2 event3 );

    Users of your class can now call the "on" method in order to register an
    event handler:

      $obj->on( event1 => sub { say "I has an event;" } );

    And clear their event listeners with:

      $obj->remove_all_listeners( 'ping' );

    You can trigger events from your class with the "trigger" method:

      $self->trigger( "event1", "arg1", "arg2", "argn" );

    You can remove the has_event and has_events helpers by unimporting
    On::Event:

      no On::Event;

HELPERS (exported subroutines)
    sub has_event( Array[Str] *@event_names ) is export
    sub has_events( Array[Str] *@event_names ) is export
        Registers your class as being able to trigger the event names
        listed.

METHODS
    our method event_exists( Str $event ) returns Bool
        Returns true if $event is a valid event name for this class.

    our method on( Str $event, CodeRef $listener ) returns CodeRef
        Registers $listener as a listener on $event. When $event is
        triggered ALL registered listeners are executed.

        Returns the listener coderef.

    our method trigger( Str $event, Array[Any] *@args )
        Normally called within the class using the On::Event role. This
        calls all of the registered listeners on $event with @args.

        If you're using coroutines then each listener will get its own
        thread and trigger will cede before returning.

    our method remove_all_listeners( Str $event )
        Removes all listeners for $event

AUTHOR
    Becca <becca@referencethis.com>

COPYRIGHT AND LICENSE
    This software is copyright (c) 2011 by Rebecca Turner.

    This is free software; you can redistribute it and/or modify it under
    the same terms as the Perl 5 programming language system itself.

