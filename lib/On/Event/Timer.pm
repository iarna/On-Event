package On::Event::Timer;
use strict;
use warnings;
# ABSTRACT: Timer/timeout events for On::Event
use Any::Moose;
use AnyEvent;
use On::Event;
use Scalar::Util;

with 'On::Event';

has 'delay'    => (isa=>'Num|CodeRef', is=>'ro', default=>0);
has 'interval' => (isa=>'Num', is=>'ro', default=>0);
has '_guard'   => (is=>'rw');
has_event 'timeout';

no On::Event;
no Any::Moose;

=head1 SYNOPSIS

    use On::Event Timer => qw( sleep sleep_until );
    
    # After five seconds, say Hi
    On::Event::Timer->after( 5, sub { say "Hi!" } );
    
    sleep 3; # Sleep for 3 seconds without blocking events from firing
    
    # Two seconds from now, say At!
    On::Event::Timer->at( time()+2, sub { say "At!" } );
    
    # Every 5 seconds, starting 5 seconds from now, say Ping
    On::Event::Timer->every( 5, sub { say "Ping" } );
    
    sleep_until time()+10; # Sleep until 10 seconds from now

=for test_synopsis
use v5.10;

=head1 DESCRIPTION

Trigger events at a specific time or after a specific delay.

=cut

sub import {
    my $class = shift;
    my $pkg = caller;
    for ( @_ ) {
        if ( !/^(?: sleep | sleep_until )$/x ) {
            require Carp;
            Carp::croak( "Can't import unknown helper $_" );
        }
        no strict 'refs'; ## no critic (ProhibitNoStrict)
        *{"$pkg\::$_"} = \&{"$class\::$_"};
    }
}

=head1 HELPERS

=over

=item our sub sleep( Rat $secs ) is export

Sleep for $secs while allowing events to emit (and Coroutine threads to run)

=back

=cut

sub sleep {
    return if $_[-1] <= 0;
    my $cv = AE::cv;
    my $w; $w=AE::timer( $_[-1], 0, sub { undef $w; $cv->send } );
    $cv->recv;
}

=over

=item our sub sleep_until( Rat $epochtime ) is export

Sleep until $epochtime while allowing events to emit (and Coroutine threads to run)

=back

=cut

sub sleep_until {
    my $for = $_[-1] - AE::time;
    return if $for <= 0;
    my $cv = AE::cv;
    my $w; $w=AE::timer( $for, 0, sub { undef $w; $cv->send } );
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
    my $self = $class->new( delay=> $after );
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
    my $self = $class->new( delay=> sub {$at - AE::time}  );
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
    my $self = $class->new( delay => $every, interval => $every );
    $self->on( timeout => $on_timeout );
    $self->start( defined(wantarray) );
    return $self;
}

=item our method new( :$delay, :$interval? ) returns On::Event::Timer

Creates a new timer object that will emit it's "timeout" event after $delay
seconds and every $interval seconds there after.  Delay can be a code ref,
in which case it's return value is the number of seconds to delay.

=back

=head1 METHODS

=over

=item our method on( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event.  When $event is emitted ALL
registered listeners are executed.

Returns the listener coderef.

=item our method emit( Str $event, Array[Any] *@args )

Normally called within the class using the On::Event role.  This calls all
of the registered listeners on $event with @args.

If you're using coroutines then each listener will get its own thread and
emit will cede before returning.

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
        $cb = sub { $self->emit('timeout') };
    }
    else {
        $cb = sub { $self->cancel; $self->emit('timeout'); }
    }
    my $delay;
    if ( ref $self->delay ) {
        $delay = $self->delay->();
        $delay = 0 if $delay < 0;
    }
    else {
        $delay = $self->delay;
    }
    my $w = AE::timer $delay, $self->interval, sub { $self->emit('timeout') };
    $self->_guard( $w );
}

=item our method cancel()

Cancels a running timer. You can start the timer again by calling the start
method.  For after and every timers, it begins waiting all over again. At timers will
still emit at the time you specified (or immediately if that time has passed).

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

This event takes no arguments.  It's emitted when the event time completes.

=back

=head1 SEE ALSO

=over

=item * L<AnyEvent>

=item * L<http://nodejs.org/docs/v0.5.4/api/timers.html>

=back

=cut

1;
