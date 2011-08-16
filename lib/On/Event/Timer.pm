package On::Event::Timer;
# ABSTRACT: Timer/timeout events for On::Event
use strict;
use warnings;
use Any::Moose;
use AnyEvent;
use On::Event;
use Scalar::Util;

with 'On::Event';

has 'in'    => (isa=>'Num', is=>'ro', default=>0);
has 'interval' => (isa=>'Num', is=>'ro', default=>0);
has '_guard'   => (is=>'rw');
has_event 'timeout';

no On::Event;
no Any::Moose;

sub sleep {
    my $sleep = $_[-1];
    my $cv = AE::cv;
    AE::timer( $sleep, 0, sub { $cv->send } );
    $cv->recv;
}

sub after {
    my $class = shift;
    my( $after, $on_timeout ) = @_;
    my $self = $class->new( in=> $after );
    $self->on( timeout => $on_timeout );
    $self->start( defined(wantarray) );
    return $self;
}

sub at {
    my $class = shift;
    my( $at, $on_timeout ) = @_;
    my $self = $class->new( in=> $at - AE::time );
    $self->on( timeout => $on_timeout );
    $self->start( defined(wantarray) );
    return $self;
}

sub every {
    my $class = shift;
    my( $every, $on_timeout ) = @_;
    my $self = $class->new( in => $every, interval => $every );
    $self->on( timeout => $on_timeout );
    $self->start( defined(wantarray) );
    return $self;
}

sub start {
    my $self = shift;
    my( $is_weak ) = @_;
    my $cb;
    Scalar::Util::weaken($self) if $is_weak;
    if ( $self->interval ) {
        $cb = sub { $self->trigger('timeout') };
    }
    else {
        $cb = sub { $self->cancel; $self->trigger('timeout'); }
    }
    my $w = AE::timer $self->in, $self->interval, sub { $self->trigger('timeout') };
    $self->_guard( $w );
}

sub cancel {
    my $self = shift;
    $self->_guard( undef );
}

1;
