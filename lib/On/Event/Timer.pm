package On::Event::Timer;
# ABSTRACT: Timer/timeout events for On::Event
use strict;
use warnings;
use Any::Moose;
use AnyEvent;
use On::Event;
use Scalar::Util;

with 'On::Event';

has 'in'    => (isa=>'Num|CodeRef', is=>'ro', default=>0);
has 'interval' => (isa=>'Num', is=>'ro', default=>0);
has '_guard'   => (is=>'rw');
has_event 'timeout';

no On::Event;
no Any::Moose;

sub import {
    my $class = shift;
    my $pkg = caller;
    for ( @_ ) {
        if ( $_ ne 'sleep' ) {
            require Carp;
            Carp::croak( "Can't import unknown helper $_" );
        }
    }
    no strict 'refs';
    *{"$pkg\::sleep"} = \&sleep;
}

=head1 HELPERS

=over

=item our sub sleep( Rat $secs ) is export

Uses AnyEvent to sleep for $secs

=back

=cut

sub sleep {
    my $sleep = $_[-1];
    my $cv = AE::cv;
    AE::timer( $sleep, 0, sub { $cv->send } );
    $cv->recv;
}

=head1 CLASS METHODS

=over

=item our method after( Rat $seconds, CodeRef $on_timeout ) returns On::Event::Timer

Asynchronously, after $seconds, calls $on_timeout.  If you store the return
value, it acts as a guard-- if it's destroyed then the timer is canceled.

=cut

sub after {
    my $class = shift;
    my( $after, $on_timeout ) = @_;
    my $self = $class->new( in=> $after );
    $self->on( timeout => $on_timeout );
    $self->start( defined(wantarray) );
    return $self;
}

=item our method at( Rat $epochtime, CodeRef $on_timeout ) returns On::Event::Timer

Asychronously waits until $epochtime and then calls $on_timeout. If you store the
return value, it acts as a guard-- if it's destoryed then the timer is canceled.

=cut

sub at {
    my $class = shift;
    my( $at, $on_timeout ) = @_;
    my $self = $class->new( in=> sub {$at - AE::time}  );
    $self->on( timeout => $on_timeout );
    $self->start( defined(wantarray) );
    return $self;
}

=item our method every( Rat $seconds, CodeRef $on_timeout ) returns On::Event::Timer

Asychronously, after $seconds and every $seconds there after, calls $on-Timeout.  If you
store the return value it acts as a guard-- if it's destroyed then the timer is canceled.

=cut

sub every {
    my $class = shift;
    my( $every, $on_timeout ) = @_;
    my $self = $class->new( in => $every, interval => $every );
    $self->on( timeout => $on_timeout );
    $self->start( defined(wantarray) );
    return $self;
}

=item our method new( :$in, :$interval? ) returns On::Event::Timer

Creates a new timer object that will trigger it's "timeout" event after $in
seconds and every $interval seconds there after.

=back

=head1 METHODS

=over

=item our method on( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event.  When $event is triggered ALL
registered listeners are executed.

Returns the listener coderef.

=item our method trigger( Str $event, Array[Any] *@args )

Normally called within the class using the On::Event role.  This calls all
of the registered listeners on $event with @args.

If you're using coroutines then each listener will get its own thread and
trigger will cede before returning.

=item our method remove_all_listeners( Str $event )

Removes all listeners for $event

=item our method start( $is_obj_guard = False )

Starts the timer object running.  If $is_obj_guard is true, then destroying
the object will cancel the timer.

=cut

sub start {
    my $self = shift;
    my( $is_weak ) = @_;
    
    if ( defined $self->_guard ) {
        require Carp;
        Carp::croak( "Can't start a timer that's already running" );
    }
    
    my $cb;
    Scalar::Util::weaken($self) if $is_weak;
    if ( $self->interval ) {
        $cb = sub { $self->trigger('timeout') };
    }
    else {
        $cb = sub { $self->cancel; $self->trigger('timeout'); }
    }
    my $in;
    if ( ref $self->in ) {
        $in = $self->in->();
        $in = 0 if $in < 0;
    }
    else {
        $in = $self->in;
    }
    my $w = AE::timer $in, $self->interval, sub { $self->trigger('timeout') };
    $self->_guard( $w );
}

=item our method cancel()

Cancels a running timer. You can start the timer again by calling the start
method.  For after and every timers, it begins waiting all over again. At timers will
still trigger at the time you specified (or immediately if that time has passed).

=cut

sub cancel {
    my $self = shift;
    unless (defined $self->_guard) {
        require Carp;
        Carp::croak( "Can't cancel a timer that's not running" );
    }
    $self->_guard( undef );
}

=back

=head1 EVENTS

=over

=item timeout

This event takes no arguments.  It's triggered when the event time completes.

=back

=cut

1;
