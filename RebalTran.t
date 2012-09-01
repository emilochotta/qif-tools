#!/bin/perl

# Test the functionality of RebalTran.pm use RebalTran; use base
# qw(Test::Class); use Test::More; use strict; use warnings;
use RebalTran;
use Transaction;
use Portfolio;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

sub test_new : Test(5) {
    my $t = new Transaction();
    my $p = new Portfolio();
    my $r = new RebalTran($t,$p);
    ok(defined($r), 'RebalTran object was created');
    ok($r->isa('RebalTran'), 'RebalTran object isa RebalTran');
    ok(defined($r->transaction()), 'Tran field defined');
    is($r->transaction(), $t, 'Tran field is tran');
    ok($r->transaction()->isa('Transaction'), 
      'Tran field isa Transaction');
};

Test::Class->runtests;
