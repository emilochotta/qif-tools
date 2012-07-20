#!/bin/perl

#
# Test the functionality of Account.pm
#
use Account;
use base qw(Test::Class);
use Test::More;
use Transaction qw(@MstarHeaders %MstarMap);
use strict;
use warnings;

# a test method that runs 1 test
sub test_new : Test(2) {
    my $t = new Account();
    ok(defined($t), 'Account object was created');
    ok($t->isa('Account'), 'Account object isa Account');
};

# Test reading an account from a QIF file
sub test_from_qif : Test(4) {
    my $t = Account::newFromQif('test', 1,
				'account.qif');
    ok(defined($t), 'Account object was created');
    ok($t->isa('Account'), 'Account object isa Account');
    my $raStrings = [];
    $t->printToStringArray($raStrings);
    is(@$raStrings, 102, 'Returned expected number of strings');
#    print join("\n", @$raStrings);
    my $raCsv = [];
    $t->printToCsv(\@Transaction::MstarHeaders, \%Transaction::MstarMap, undef, 
		   $raCsv);
    print join("\n", @$raCsv);
    is(@$raCsv, 7, 'Returned expected number of CSV');
};

Test::Class->runtests;
