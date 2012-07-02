#!/bin/perl

#
# Test the functionality of Ticker.pm
#
use Ticker;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# a test method that runs 1 test
sub test_ByName : Test(2) {
    my $t = Ticker::getByName('VANGUARD REIT');
    ok(defined($t), 'Ticker object was created');
    ok($t->isa('Ticker'), 'Ticker object isa ticker');
};

Test::Class->runtests;
