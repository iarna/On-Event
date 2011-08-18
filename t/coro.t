use strict;
use warnings;
use Test::More tests => 2;
eval 'use Coro';
if ( $@ ) {
   skip( "Can't do Coro tests without Coro installed", 2);
   exit;
}
use On::Event::Timer qw( sleep );

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

$te->trigger( "ping" );
