#!/bin/perl

#
# Test the functionality of Transaction.pm
#
use Transaction;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# Test basic object creation
sub test_new : Test(2) {
    my $t = new Transaction();
    ok(defined($t), 'Transaction object was created');
    ok($t->isa('Transaction'), 'Transaction object isa Transaction');
};

# Test creation from QIF record.
sub test_newFromQif : Test(19) {
    # Cash transaction
    my $t1 = Transaction::newFromQifRecord( {
	'account' => '[Van Brokerage]',
	'action' => 'Cash',
	'date' => "11/ 7'10",
	'header' => 'Type:Invst',
	'status' => 'R' });
    ok(defined($t1), 'Transaction object was created');
    ok($t1->isa('Transaction'), 'Transaction object isa Transaction');
    is($t1->date(), '11-7-2010', 'date okay');
    is($t1->action(), 'Cash', 'action cash okay');
    is($t1->symbol(), 'Cash', 'symbol cash okay');
    is($t1->symbol(), $t1->ticker()->symbol(),
       'symbol matches ticker');
    is($t1->amount(), $t1->shares() * $t1->price() + $t1->commision(),
       'amount was shares*price + commision');

    my $t2 = Transaction::newFromQifRecord( {
	'action' => 'Buy',
	'date' => "11/ 8'10",
	'header' => 'Type:Invst',
	'memo' => 'BUY',
	'price' => '71.1984',
	'quantity' => '1200',
	'security' => 'VANGUARD MID CAP ETF',
	'status' => 'R',
	'total' => '85438.08',
	'transaction' => '85438.08', });
    ok(defined($t2), 'Transaction object was created');
    ok($t2->isa('Transaction'), 'Transaction object isa Transaction');
    is($t2->date(), '11-8-2010', 'date okay');
    is($t2->action(), 'Buy', 'action Buy okay');
    is($t2->symbol(), 'VO', 'symbol okay');
    is($t2->symbol(), $t2->ticker()->symbol(),
       'symbol matches ticker');

    my $t3 = Transaction::newFromQifRecord( {
	'action' => 'ReinvDiv',
	'date' => "12/31'10",
	'header' => 'Type:Invst',
	'memo' => 'DIVIDEND REINVESTMENTDIVIDEND REINVESTMENT',
	'price' => '74.643187',
	'quantity' => '14.083',
	'security' => 'VANGUARD MID CAP ETF',
	'status' => 'R',
	'total' => '1051.20',
	'transaction' => '1051.20', } );
    ok(defined($t3), 'Transaction object was created');
    ok($t3->isa('Transaction'), 'Transaction object isa Transaction');
    is($t3->date(), '12-31-2010', 'date okay');
    is($t3->action(), 'ReinvDiv', 'action reinvdiv okay');
    is($t3->symbol(), 'VO', 'symbol okay');
    is($t3->symbol(), $t3->ticker()->symbol(),
       'symbol matches ticker');

    # Tickers should be reused.
    is($t2->ticker(), $t3->ticker(), 'tickers are reused');
};

Test::Class->runtests;
