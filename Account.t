#!/bin/perl

#
# Test the functionality of Account.pm
#
use Account;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# a test method that runs 1 test
sub test_new : Test(2) {
    my $t = new Account();
    ok(defined($t), 'Account object was created');
    ok($t->isa('Account'), 'Account object isa Account');
};

# Test reading an account from a QIF file
sub test_from_qif : Test(3) {
    my $t = Account::newFromQif('test', 1,
				'account.qif');
    ok(defined($t), 'Account object was created');
    ok($t->isa('Account'), 'Account object isa Account');
    my $raStrings = [];
    $t->printToStringArray($raStrings);
    is(@$raStrings, 97, 'Returned expected number of strings');
    print join("\n", @$raStrings);
};

Test::Class->runtests;
