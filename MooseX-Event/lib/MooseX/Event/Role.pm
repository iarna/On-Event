# ABSTRACT: A Node style event Role for Moose
package MooseX::Event::Role;
use MooseX::Event ();
use Any::Moose 'Role';

has '_listeners'    => (isa=>'HashRef', is=>'ro', default=>sub{ {} });
has '_aliases'      => (isa=>'HashRef', is=>'ro', default=>sub{ {} });

=attr our Str $.current_event is rw

This is the name of the current event being triggered, or undef if no event
is being triggered.

=cut

has 'current_event' => (isa=>'Str|Undef', is=>'rw');

=event new_listener( Str $event, CodeRef $listener )

Called when a listener is added.  $event is the name of the event being listened to, and $listener is the
listener being installed.

=cut

MooseX::Event::has_event('new_listener');

=method our method event_exists( Str $event ) returns Bool

Returns true if $event is a valid event name for this class.

=cut

sub event_exists {
    my $self = shift;
    my( $event ) = @_;
    return $self->can("event:$event");
}

=method our method on( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event.  When $event is emitted ALL
registered listeners are executed.

Returns the listener coderef.

=cut

sub on {
    my $self = shift;
    my( $event, $listener, @wrappers ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->_listeners->{$event} ||= [];
    $self->_aliases->{$event} ||= {};
    if ( ! @{$self->_listeners->{$event}} and $self->can('activate_event') ) {
        $self->activate_event($event);
    }
    my @aliases;
    my $wrapped = $listener;
    for ( reverse(@wrappers), reverse(@MooseX::Event::listener_wrappers) ) {
        push @aliases, 0+$wrapped;
        $wrapped = $_->( $wrapped );
    }
    $self->_aliases->{$event}{0+$wrapped} = \@aliases;
    for ( @aliases ) {
        $self->_aliases->{$event}{$_} = $wrapped;
    }
    $self->emit('new_listener', $event, $wrapped);
    push @{ $self->_listeners->{$event} }, $wrapped;
    return $wrapped;
}

=method our method once( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event. Event listeners registered via
once will emit only once.

Returns the listener coderef.

=cut

sub once {
    my $self = shift;
    $self->on( @_, sub {
        my($listener) = @_;
        my $wrapped;
        $wrapped = sub {
            my $self = shift;
            $self->remove_listener($self->current_event=>$wrapped);
            $wrapped=undef;
            goto $listener;
        };
        return $wrapped;
    });
}

BEGIN {

=begin internal

=method my method emit_stock( Str $event, Array[Any] *@args )

The standard impelementation of the emit method-- calls the listeners
immediately and in the order they were defined.

=end internal

=cut

    my $emit_stock = sub {
        my $self = shift;
        my( $event, @args ) = @_;
        if ( ! $self->event_exists($event) ) {
            die "Event $event does not exist";
        }
        return unless exists $self->_listeners->{$event};
        my $ce = $self->current_event;
        $self->current_event( $event );
        foreach ( @{ $self->_listeners->{$event} } ) {
            $_->($self,@args);
        }
        $self->current_event($ce);
        return;
    };

=begin internal

=method my method emit_coro( Str $event, Array[Any] *@args )

The L<Coro> implementation of the emit method-- calls each of the listeners
in its own thread and emits immediate execution by calling cede before
returning.

=end internal

=cut

    my $emit_coro = sub {
        my $self = shift;
        my( $event, @args ) = @_;
        if ( ! $self->event_exists($event) ) {
            die "Event $event does not exist";
        }
        return unless exists $self->_listeners->{$event};

        foreach my $todo ( @{ $self->_listeners->{$event} } ) {
            my $ce;
            &Coro::async( sub {
                &Coro::on_enter( sub {
                    $ce  = $self->current_event;
                    $self->current_event($event);
                });
                $todo->(@_);
                &Coro::on_leave( sub {
                    $self->current_event($ce);
                });
            }, $self, @args );
        }
        Coro::cede();

        return;
    };

=method our method emit( Str $event, Array[Any] *@args )

Normally called within the class using the MooseX::Event role.  This calls all
of the registered listeners on $event with @args.

If you're using coroutines then each listener will get its own thread and
emit will cede before returning.

=cut

    sub emit {
        no warnings 'redefine';
        if ( defined *Coro::async{CODE} ) {
            *emit = $emit_coro;
            goto $emit_coro;
        }
        else {
            *emit = $emit_stock;
            goto $emit_stock;
        }
    }

}

=method our method remove_all_listeners( Str $event )

Removes all listeners for $event

=cut

sub remove_all_listeners {
    my $self = shift;
    if ( @_ ) {
        my( $event ) = @_;
        delete $self->_listeners->{$event};
        delete $self->_aliases->{$event};
        if ( $self->can('deactivate_event') ) {
            $self->deactivate_event($event);
        }
    }
    else {
        if ( $self->can('deactivate_event') ) {
            for ( keys %{$self->_listeners} ) {
                $self->deactivate_event($_);
            }
        }
        %{ $self->_listeners } = ();
        %{ $self->_aliases } = ();
    }
}

=method our method remove_listener( Str $event, CodeRef $listener )

Removes $listener from $event

=cut

sub remove_listener {
    my $self = shift;
    my( $event, $listener ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->_listeners->{$event};
    
    my $aliases = $self->_aliases->{$event}{0+$listener};
    delete $self->_aliases->{$event}{0+$listener};
    
    if ( ref $aliases eq "ARRAY" ) {
        for ( @$aliases ) {
            delete $self->_aliases->{$event}{$_};
        }
    }
    else {
        $listener = $aliases;
    }

    $self->_listeners->{$event} =
        [ grep { $_ != $listener } @{ $self->_listeners->{$event} } ];
        
    if ( ! @{$self->_listeners->{$event}} and $self->can('deactivate_event') ) {
        $self->deactivate_event($event);
    }
}

1;

=pod

=head1 DESCRIPTION

This is the role that L<MooseX::Event> extends your class with.  All classes
using MooseX::Event will have these methods, attributes and events.

=head1 SEE ALSO

MooseX::Event::Role::ClassMethods
