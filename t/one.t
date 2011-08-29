use strict;
use warnings;
use Test::More tests => 3;
use ONE qw( Timer=sleep );

my $one = ONE->instance;

my $ii = 0;
my $idle = $one->on( idle => sub { $ii ++ } );

# We're also testing loop and stop here
ONE::Timer->after( 0.1 => sub { ONE->stop } );
ONE->loop;

cmp_ok( $ii, '>', 1000, "The idle counter ticked a reasonable number of times." );

$one->remove_listener( idle =>$idle );

$ii = 0;

sleep .1;

is( $ii, 0, "The idle counter did not tick after we removed it" );

my $alarm = 0;
$one->on( SIGALRM => sub { $alarm ++ } );
alarm(1);
sleep 1.1;
alarm(0);

is( $alarm, 1, "The alarm signal triggered" );
