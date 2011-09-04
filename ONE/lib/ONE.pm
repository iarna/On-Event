# ABSTRACT: A Node.js style AnyEvent class, using MooseX::Event
package ONE;
use AnyEvent;
use ONE::Collect;
use MooseX::Event;

with 'MooseX::Event::Role::ClassMethods';

=helper collect { ... }

Will return after all of the events declared inside the collect block have
been emitted at least once.

=cut

sub collect (&) {
    my $collect = ONE::Collect->new();
    my $wrapper = MooseX::Event->add_listener_wrapper( sub {
        my( $todo ) = @_;
        $collect->listener( $todo );
    } );
    $_[0]->();
    MooseX::Event->remove_listener_wrapper( $wrapper );
    $collect->complete;
}

has '_loop_cv' => (is=>'rw', init_arg=>undef);
has '_idle_cv' => (is=>'rw', init_arg=>undef );
has '_signal'  => (is=>'rw', default=>sub{{}}, init_arg=>undef);

=event idle

This is an AnyEvent idle watcher.  It will repeatedly invoke the listener
whenever the process is idle.  Several thousand times per second on a
moderately loaded system.  Attaching a once listener to this will let you
defer code until any active events have finished processing. 
              
=cut

=event SIG*

You can register event listeners for any of the following events:

    SIGHUP   SIGINT  SIGQUIT SIGILL  SIGTRAP SIGABRT SIGBUS    SIGFPE    SIGKILL
    SIGUSR1  SIGSEGV SIGUSR2 SIGPIPE SIGALRM SIGTERM SIGSTKFLT SIGCHLD   SIGCONT
    SIGSTOP  SIGTSTP SIGTTIN SIGTTOU SIGURG  SIGXCPU SIGXFSZ   SIGVTALRM SIGPROF
    SIGWINCH SIGIO   SIGPWR  SIGSYS

Some of these may not actually be catchable (ie, SIGKILL), this is just the
list from "kill -l" on a modern Linux system.  Using one of these installs
any AnyEvent signal watcher.  As with AnyEvent, this will work

=cut

has_events qw(
    idle 
    SIGHUP   SIGINT  SIGQUIT SIGILL  SIGTRAP SIGABRT SIGBUS    SIGFPE    SIGKILL
    SIGUSR1  SIGSEGV SIGUSR2 SIGPIPE SIGALRM SIGTERM SIGSTKFLT SIGCHLD   SIGCONT
    SIGSTOP  SIGTSTP SIGTTIN SIGTTOU SIGURG  SIGXCPU SIGXFSZ   SIGVTALRM SIGPROF
    SIGWINCH SIGIO   SIGPWR  SIGSYS );



=classmethod our method instance() returns ONE

Return the singleton object for this class

=cut

# We would just use MooseX::Singleton, but it's nice to maintain compatibility with Mouse
BEGIN {
    my $instance;
    sub instance {
        my $class = shift;
        return $instance ||= $class->new(@_);
    }
}


=for internal

=head1 our method activate_event( $event )

This method is called by MooseX::Event when the first event listener for a
particular event is registered.  We use this to start the AE::idle or
AE::signal event listeners.  We wouldn't want them running when the user has
no active listeners.

=cut

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

=for internal

=head1 our method deactivate_event( $event )

This method is called by MooseX::Event when the last event listener for a
particular event is removed.  We use this to shutdown the AE::idle or
AE::signal event listeners when the last acitve listener is removed.

=cut

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

=classmethod our method loop()

Starts the main event loop.  This will return when the stop method is
called.  If you call start with an already active loop, the previous loop
will be stopped and a new one started.

=cut

sub loop {
    my $cors = shift;
    my $self = ref $cors ? $cors : $cors->instance;
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
    my $self = ref $cors ? $cors : $cors->instance;
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
    *{$caller.'::collect'} = $class->can('collect');
}

=for internal

=head1 our method unimport()

Removes the collect helper method

=cut

sub unimport {
    my $caller = caller;
    no strict 'refs';
    delete ${$caller.'::'}{'collect'};
}

__PACKAGE__->meta->make_immutable();
no MooseX::Event;

1;

=pod

=head1 SYNOPSIS

# General event loop:

    use ONE;
    
    ONE->start;

# Collation:

    use ONE;
    use ONE::Timer;
    
    collect {
         ONE::Timer->after( 2 => sub { say "two" } );
         ONE::Timer->after( 3 => sub { say "three" } );
    }; # After three seconds will have printed "two" and "three"

=for test_synopsis
use v5.10.0;

=head1 DESCRIPTION

=cut
