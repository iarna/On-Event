package ONE::Collate;
use strict;
use warnings;
use AnyEvent;
use Any::Moose;

has '_cv' => (isa=>'AnyEvent::CondVar', is=>'rw');

=method our listener( CodeRef $todo )

Capture the $todo listener, such that collate will trigger when this and all
other listeners trigger.

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

    
    # Here we wrap the event listener and,a fter the first call, remove
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


=method our collate()

Wait for all of the captured events to trigger at least once.

=cut

sub collate {
    my $self = shift;
    return unless defined $self->_cv;
    $self->_cv->wait;
}


#sleep(5) ~~ collate { ONE::Timer->after( 5, listener {} ) }

__PACKAGE__->meta->make_immutable();
no Any::Moose;


1;
