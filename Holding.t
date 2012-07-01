#!/bin/perl

#
# Test the functionality of Holding.pm
#
use Holding;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# a test method that runs 1 test
sub test_new : Test(2) {
    my $t = new Holding();
    ok(defined($t), 'Holding object was created');
    ok($t->isa('Holding'), 'Holding object isa Holding');
};

Test::Class->runtests;
