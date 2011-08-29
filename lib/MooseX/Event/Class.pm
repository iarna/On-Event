# ABSTRACT: Make MooseX::Event methods available as class methods on a singleton
package MooseX::Event::Class;
use strict;
use warnings;
use namespace::autoclean;
use Any::Moose 'Role';

requires 'instance';

around [qw( event_exists on once emit remove_all_listeners remove_listener )] => sub {
    my $orig = shift;
    if ( ! ref $_[0] ) {
        my $class = shift;
        unshift @_, $class->instance;
    }
    goto $orig;
};

no Any::Moose 'Role';

1;

=pod

=head1 SYNOPSIS

  package Example;
  use common::sense;
  use MooseX::Singleton;
  use MooseX::Event qw( -nomagic );
  
  with 'MooseX::Event::Class';
  
  
  has_event 'pinged';
  
  sub ping {
      my $self = shift;
      $self->emit('pinged');
  }
  
  package main;
  Example->on( pinged => sub { say "Got a ping!" } );
  Example->on( pinged => sub { say "Got another ping!" } );
  Example->ping; # prints "Got a ping!" and "Got another ping!"
  Example->remove_all_listeners( "pinged" ); # Remove all of the pinged listeners
  Example->once( pinged => sub { say "First ping." } );
  Example->ping; Example->ping; # Only prints "First ping." once
  my $listener = Example->on( pinged => sub { say "Ping" } );
  Example->remove_listener( pinged => $listener );
  Example->ping(); # Does nothing

=head1 DESCRIPTION

Sometimes it's handy to be able to call object methods directly on a
singleton class, without having to call instance yourself.  This wraps up
the MooseX::Event Role to allow this.  Your class must provide an instance
method that returns the singleton object.  One way to do this is with the
MooseX::Singleton class, as in the example, but you can easily role your own
if you prefer.

=head1 SEE ALSO

MooseX::Event
