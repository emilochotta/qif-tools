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
sub test_new : Test(29) {
    my $t2 = Transaction::newFromQifRecord( {
	'action' => 'Buy',
	'date' => "11/ 8'10",
	'header' => 'Type:Invst',
	'memo' => 'BUY',
	'price' => '12.3456',
	'quantity' => '100',
	'security' => 'VANGUARD MID CAP ETF',
	'status' => 'R',
	'total' => '1234.56',
	'transaction' => '1234.56', });
    ok(defined($t2), 'Transaction object was created');
    ok($t2->isa('Transaction'), 'Transaction object isa Transaction');

    my $t3 = Transaction::newFromQifRecord( {
	'action' => 'ReinvDiv',
	'date' => "12/31'10",
	'header' => 'Type:Invst',
	'memo' => 'DIVIDEND REINVESTMENTDIVIDEND REINVESTMENT',
	'price' => '5',
	'quantity' => '100',
	'commission' => '10',
	'security' => 'VANGUARD MID CAP ETF',
	'status' => 'R',
	'total' => '510',
	'transaction' => '510', } );
    ok(defined($t3), 'Transaction object was created');
    ok($t3->isa('Transaction'), 'Transaction object isa Transaction');

    my $ticker = Ticker::getByName('VANGUARD MID CAP ETF');

    my $h = new Holding($ticker);
    ok(defined($h), 'Holding object was created');
    ok($h->isa('Holding'), 'Holding object isa Holding');

    $h->appendTransaction($t2);
    my @a = @{$h->transactions()};
    is(scalar(@a), 1, 'Right number of Transactions');
    my $trans = $a[0];
    is($trans->ticker(), $h->ticker(), 'Tickers match');

    $h->appendTransaction($t3);
    @a = @{$h->transactions()};
    is(scalar(@a), 2, 'Right number of Transactions');
    $trans = $a[1];
    is($trans->ticker(), $h->ticker(), 'Tickers match');

    $h->computeAllFromTransactions();
    is($h->shares(), 200, 'Right number of shares');

    my $h2 = $h->newDeepCopy();
    ok(defined($h2), 'h2 object was created');
    ok($h2->isa('Holding'), 'h2 object isa Holding');
    is($h->ticker(), $h2->ticker(), "ticker matches");
    is($h->inAccount(), $h2->inAccount(), "inAccount matches");
    is($h->shares(), $h2->shares(), "shares matches");
    is($h->price(), $h2->price(), "price matches");
    is($h->estimated(), $h2->estimated(), "estimated matches");
    is($h->cost_basis(), $h2->cost_basis(), "cost_basis matches");
    is($h->gain(), $h2->gain(), "gain matches");
    is($h->value(), $h2->value(), "value matches");
    is($h->purchases(), $h2->purchases(), "purchases matches");
    is($h->myReturn(), $h2->myReturn(), "myReturn matches");
    is($h->hasNewTrans(), $h2->hasNewTrans(), "hasNewTrans matches");
    
    ok(defined($h2->transactions()), 'h2 transactions defined');
    ok($h2->transactions()->isa('Transactions'), 'h2 transactions isa transactions');

    @a = @{$h2->transactions()};
    is(scalar(@a), 2, 'Right number of Transactions');
    $trans = $a[1];
    is($trans->ticker(), $h2->ticker(), 'Tickers match');

    $h2->computeAllFromTransactions();
    is($h2->shares(), 200, 'Right number of shares');
};

Test::Class->runtests;
