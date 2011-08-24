package ONE::Loop;
# Dist::Zilla: +PodWeaver
# ABSTRACT: A starter for the base event loop
use strict;
use warnings;
use AnyEvent;
use Scalar::Util;

=head1 SYNOPSIS

    use ONE::Loop;
    
    ONE::Loop->start;

=for test_synopsis
use v5.10;

=head1 OVERVIEW

Starts up the event loop's main loop.

=classmethod our method start()

Starts the event loop's main loop and never returns.

=cut

sub start {
    AE::cv->recv();
}

1;
