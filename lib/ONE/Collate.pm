package ONE::Collate;
use strict;
use warnings;
use AnyEvent;
use Any::Moose;

BEGIN {
    our $collater;
    sub cmd_collate (&) {
        local $collater = ONE::Collate->new();
        $_[0]->();
        $collater->collate;
    }
    sub cmd_listener (&) {
        my $todo = shift;
        return defined $collater ? $collater->listener($todo) : $todo;
    }
=pod
    sub cmd_collate(&) {
        local $cv;
        $_[0]->();
        $cv->wait if defined $cv;
    }
    
    sub cmd_listener (&) {
        my $todo = shift;
        $cv ||= AE::cv;
        if ($cv == -1) {
            return $todo;
        }
        $cv->begin;
        return sub { $todo->(@_); $cv->end };
    }
=cut
}

sub import {
    my $class = shift;
    my $caller = caller;
    
    no strict 'refs';
    *{$caller.'::collate'} = $class->can('cmd_collate');
    *{$caller.'::listener'} = $class->can('cmd_listener');
}

sub unimport {
    my $caller = caller;
    no strict 'refs';
    delete ${$caller.'::'}{'collate'};
    delete ${$caller.'::'}{'listener'};
}

has '_cv' => (isa=>'AnyEvent::CondVar', is=>'rw');

sub listener {
    my $self = shift;
    my( $todo ) = @_;
    my $cv = $self->_cv;
    unless ( $cv ) {
        $self->_cv( $cv = AE::cv );
    }
    $cv->begin;
    return sub { $todo->(@_); $cv->end };
}

sub collate {
    my $self = shift;
    return unless defined $self->_cv;
    $self->_cv->wait;
}


#sleep(5) ~~ collate { ONE::Timer->after( 5, listener {} ) }


1;
