#!/bin/perl

#
# Test the functionality of Transactions.pm
#
use Transactions;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# a test method that runs 1 test
sub test_new : Test(2) {
    my $t = new Transactions();
    ok(defined($t), 'Transactions object was created');
    ok($t->isa('Transactions'), 'Transactions object isa Transactions');
};

Test::Class->runtests;
