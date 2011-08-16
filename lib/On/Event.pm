package On::Event;
use strict;
use warnings;
use Any::Moose;

has 'autoload' => (isa=>'Bool', is=>'rw', default=>1);
has '_events' => (isa=>'Hash', is=>'ro', default=>sub{{}});

sub import {
    my $class = shift;
    foreach my $module ( @_ ) {
        $class = "Event::On::$module"; ;
        eval qq{ use $class; };
        die $@ if $@;
    }
}

sub event_exists { 0 }

sub on {
    my $self = shift;
    my( $event, $action ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->{_events}{$event} //= [];
    push @{ $self->{_events}{$event} }, $action;
}

sub trigger {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_events}{$event};
    foreach ( @{ $self->{_events}{$event} } ) {
        $_->(@args);
    }
    return;
}

sub clear_all_events {
    my $self = shift;
    my( $event ) = @_;
    delete $self->{_events}{$event};
}


no Any::Moose;
__PACKAGE__->meta->make_immutable();

1;
