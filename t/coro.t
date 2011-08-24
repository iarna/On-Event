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

use ONE::Timer qw( sleep );

BEGIN {
    package TestEvent;
    use strict;
    use warnings;
    use ONE;

    has_event 'ping';

    no ONE; 
}

my $te = TestEvent->new;

$te->on( ping => sub {
    pass( "Got first ping" );
    } );

$te->on( ping => sub {
    pass( "Got second ping" );
    } );

$te->emit( "ping" );
