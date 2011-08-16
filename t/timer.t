use strict;
use warnings;
use Test::More tests => 5;

use On::Event qw( Timer );

sub ae_sleep {
    my( $time ) = @_;
    my $cv = AE::cv;
    my $w; $w = AE::timer $time, 0, sub { $cv->send };
    $cv->wait;
}

my $after_test;
On::Event::Timer->after( .1, sub { $after_test ++ } );

my $at_test;
On::Event::Timer->at( AE::time+.2, sub { $at_test ++ } );

my $every_test;
my $every = On::Event::Timer->every( .3, sub { $every_test ++ });

ae_sleep(.7);

is( $after_test, 1, "After event triggered" );

is( $at_test, 1, "At event triggered" );

is( $every_test, 2, "Every test triggered twice" );

$every->cancel;

ae_sleep(.3);

is($every_test,2,"No further 'every' timer ticks have occured.");

my $cancel_test;
my $ct = On::Event::Timer->after( .1, sub { $cancel_test++ } );
$ct->cancel;
ae_sleep(.2);

isnt( $cancel_test, 1, "Canceled event doesn't occur" );

