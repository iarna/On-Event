use strict;
use warnings;
require Test::More;

eval 'use Coro';

if ( $@ ) {
    Test::More->import( skip_all => "Can't do Coro tests without Coro installed" );
    exit(0);
}
else  {
    Test::More->import( tests => 2);
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

$te->emit( "ping" );
