package ONE;
# Dist::Zilla: +PodWeaver
# ABSTRACT: A starter for the base event loop
use strict;
use warnings;
use AnyEvent;
use ONE::Collate;
use Any::Moose;
use MooseX::Event qw( -nomagic );

with 'MooseX::Event' => {};

=head1 SYNOPSIS

General event loop:

    use ONE;
    
    ONE->start;

Collation:
    use ONE::Timer;
    
    collate {
         ONE::Timer->after( 2 => sub { say "two" } );
         ONE::Timer->after( 3 => sub { say "three" } );
    }; # After three seconds will have printed "two" and "three"

=for test_synopsis
use v5.10;

=head1 OVERVIEW

=cut

BEGIN {
    our $collater;
    sub cmd_collate (&) {
        my $collater = ONE::Collate->new();
        my $wrapper = MooseX::Event->add_listener_wrapper( sub {
            my( $todo ) = @_;
            $collater->listener( $todo );
        } );
        $_[0]->();
        MooseX::Event->remove_listener_wrapper( $wrapper );
        $collater->collate;
    }
}

=helper collate { ... }

Will return after all of the events declared inside the collate block have
been emitted at least once.

=cut

has '_loop_cv' => (isa=>'AnyEvent::CondVar|Undef', is=>'rw');
has '_idle_cv' => (isa=>'Ref|Undef', is=>'rw');
has '_signal'  => (isa=>'HashRef[AnyEvent::Guard]', is=>'rw', default=>sub{{}});

has_events qw(
    idle 
    SIGHUP   SIGINT  SIGQUIT SIGILL  SIGTRAP SIGABRT SIGBUS    SIGFPE    SIGKILL
    SIGUSR1  SIGSEGV SIGUSR2 SIGPIPE SIGALRM SIGTERM SIGSTKFLT SIGCHLD   SIGCONT
    SIGSTOP  SIGTSTP SIGTTIN SIGTTOU SIGURG  SIGXCPU SIGXFSZ   SIGVTALRM SIGPROF
    SIGWINCH SIGIO   SIGPWR  SIGSYS );

sub activate_event {
    my $self = shift;
    my( $event ) = @_;
    if ( $event eq 'idle' ) {
        $self->_idle_cv( AE::idle( sub { $self->emit('idle'); } ) );
    }
    elsif ( $event =~ /^SIG([\w\d]+)$/ ) {
        my $sig  = $1;
        $self->_signal->{$sig} = AE::signal $sig, sub { $self->emit("SIG$sig") };
    }
}

sub deactivate_event {
    my $self = shift;
    my( $event ) = @_;
    if ( $event eq 'idle' ) {
        $self->_idle_cv( undef );
    }
    elsif ( $event =~ /^SIG([\w\d]+)$/ ) {
        delete $self->_signal->{$1};
    } 
}

=classmethod our method instance() returns ONE


=cut

my $self;

sub instance {
    my $class = shift;
    return $self ||= $class->new;
}

=classmethod our method loop()

Starts the main event loop.

=cut


sub loop {
    my $cors = shift;
    $self = ref $cors ? $cors : $cors->instance;
    if ( defined $self->_loop_cv ) {
        $self->_loop_cv->send();
    }
    my $cv = AE::cv;
    $self->_loop_cv( $cv );
    $cv->recv();
}

=classmethod our method stop() 

Exits the main event loop.

=cut

sub stop {
    my $cors = shift;
    $self = ref $cors ? $cors : $cors->instance;
    return unless defined $self->_loop_cv;
    $self->_loop_cv->send();
    delete $self->{'_loop_cv'};
}

sub import {
    my $class = shift;
    my $caller = caller;
    
    for (@_) {
        my($module,$args) = split /=/;
        my @args = split /[:]/, $args || "";

        local $@;
        eval "require ONE::$module;"; 
        if ( $@ ) {
            require Carp;
            Carp::croak( $@ );
        }
        eval "package $caller; ONE::$module->import(\@args);" if @args or !/=/;
        if ( $@ ) {
            require Carp;
            Carp::croak( $@ );
        }
    }
    
    no strict 'refs';
    *{$caller.'::collate'} = $class->can('cmd_collate');
}

=for internal

=classmethod our method unimport()

Removes the collate helper method

=cut

sub unimport {
    my $caller = caller;
    no strict 'refs';
    delete ${$caller.'::'}{'collate'};
}


1;
