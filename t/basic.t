use strict;
use warnings;
use Test::More tests => 2;

BEGIN {
    package TestEvent;
    use On::Event;
    use Any::Moose;

    with 'On::Event';

    has_event 'ping';

    no On::Event; 
    no Any::Moose;
}

my $te = TestEvent->new;

$te->on( ping => sub {
    pass( "Got first ping" );
    } );

$te->on( ping => sub {
    pass( "Got second ping" );
    } );

$te->emit( "ping" );
