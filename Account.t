#!/bin/perl

#
# Test the functionality of Account.pm
#
use Account;
use Holding;
use Transactions;
use base qw(Test::Class);
use Test::More;
use Transaction qw(@MstarHeaders %MstarMap);
use strict;
use warnings;

# a test method that runs 1 test
sub test_new : Test(2) {
    my $a = new Account();
    ok(defined($a), 'Account object was created');
    ok($a->isa('Account'), 'Account object isa Account');
};

# Test reading an account from a QIF file
sub test_from_qif : Test(11) {
    my $a = Account::newFromQif('account', 'account.qif');
    ok(defined($a), 'Account object was created');
    ok($a->isa('Account'), 'Account object isa Account');
    is($a->name(), 'account', 'Set Name as Expected.');
    is($a->qif_filename(), 'account.qif', 'Set Filename as Expected.');
    is(ref($a->holdings()), 'HASH', 'Holdings are a hash');
    my @k = keys %{$a->holdings()};
    is(scalar(@k), 4, 'Right number of Holdings');
    ok($a->holding('GLD')->isa('Holding'), 'Can Get a Holding');
    is($a->holding('GLD')->shares(), 95, 'Right number of shares.');
    my $t = $a->holding('GLD')->transactions();
    is(ref($t), 'Transactions', 'Transactions is correct object.');
    # is(ref($t->getArray()), 'ARRAY', 'Get array of transactions.');

    my $raStrings = [];
    $a->printToStringArray($raStrings,
			   '',  # Prefix
			   1);  # Print Transactions
    is(@$raStrings, 113, 'Returned expected number of strings');
    # print join("\n", @$raStrings);
    my $raCsv = [];
    $a->printToCsvString(\@Transaction::MstarHeaders, \%Transaction::MstarMap,
		   undef, $raCsv);
    # print join("\n", @$raCsv);
    is(@$raCsv, 7, 'Returned expected number of CSV');
};

Test::Class->runtests;
