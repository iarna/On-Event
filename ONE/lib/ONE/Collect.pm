# ABSTRACT: Collect 
package ONE::Collect;
use strict;
use warnings;
use AnyEvent;
use Any::Moose;

has '_cv' => (isa=>'AnyEvent::CondVar', is=>'rw');

=method our listener( CodeRef $todo )

This wraps the $todo listener for later use by the complete method.

=cut

sub listener {
    my $self = shift;
    my( $todo ) = @_;
    
    # Create a new CV if we don't have one yet
    my $cv = $self->_cv;
    unless ( $cv ) {
        $self->_cv( $cv = AE::cv );
    }

    # Begin processing
    $cv->begin;

    # Here we wrap the event listener and, after the first call, remove ourselves
    my $wrapped;
    $wrapped = sub { 
        my $self = shift;
        $self->remove_listener( $self->current_event, $wrapped );
        $self->on( $self->current_event, $todo );
        $todo->(@_); 
        $cv->end;
        undef $wrapped;
    };
    return $wrapped;
}


=method our complete()

Wait until all of the wrapped events have triggered at least once.

=cut

sub complete {
    my $self = shift;
    return unless defined $self->_cv;
    $self->_cv->wait;
}


__PACKAGE__->meta->make_immutable();
no Any::Moose;


1;

=head1 DESCRIPTION

