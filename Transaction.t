#!/bin/perl

#
# Test the functionality of Transaction.pm
#
use Transaction;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# a test method that runs 1 test
sub test_new : Test(2) {
    my $t = new Transaction();
    ok(defined($t), 'Transaction object was created');
    ok($t->isa('Transaction'), 'Transaction object isa Transaction');
};

Test::Class->runtests;
