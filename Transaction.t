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
sub test_newFromQif : Test(34) {
    # Cash transaction
    my $t1 = Transaction::newFromQifRecord( {
	'account' => '[Van Brokerage]',
	'action' => 'Cash',
	'date' => "11/ 7'10",
	'header' => 'Type:Invst',
	'status' => 'R' });
    ok(!defined($t1), 'Transaction without total was not created');

    $t1 = Transaction::newFromQifRecord( {
	'account' => '[Van Brokerage]',
	'action' => 'Cash',
	'date' => "11/ 7'10",
	'header' => 'Type:Invst',
	'status' => 'R',
	'total' => '1000'});
    ok(defined($t1), 'Transaction object was created');
    ok($t1->isa('Transaction'), 'Transaction object isa Transaction');
    is($t1->date(), '11-7-2010', 'date okay');
    is($t1->action(), 'Cash', 'action cash okay');
    is($t1->symbol(), 'Cash', 'symbol cash okay');
    is($t1->symbol(), $t1->ticker()->symbol(),
       'symbol matches ticker');
    is($t1->amount(), $t1->shares() * $t1->price() + $t1->commision(),
       'amount was shares*price + commision');

    $t1 = Transaction::newFromQifRecord( {
	'account' => '[Van Brokerage]',
	'action' => 'Cash',
	'date' => "11/ 7'10",
	'header' => 'Type:Invst',
	'status' => 'R',
	'transaction' => '1000'});
    ok(defined($t1), 'Transaction object was created');
    ok($t1->isa('Transaction'), 'Transaction object isa Transaction');
    is($t1->date(), '11-7-2010', 'date okay');
    is($t1->action(), 'Cash', 'action cash okay');
    is($t1->symbol(), 'Cash', 'symbol cash okay');
    is($t1->symbol(), $t1->ticker()->symbol(),
       'symbol matches ticker');
    is($t1->amount(), $t1->shares() * $t1->price() + $t1->commision(),
       'amount was shares*price + commision');

#     is(eval($t1 = Transaction::newFromQifRecord( {
# 	'account' => '[Van Brokerage]',
# 	'action' => 'Cash',
# 	'date' => "11/ 7'10",
# 	'header' => 'Type:Invst',
# 	'status' => 'R',
# 	'total' => '999',
# 	'transaction' => '1000'})), 'Date: "11-7-2010": Transaction != Total',
#        'Got exception if total != transaction');

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
    is($t2->date(), '11-8-2010', 'date okay');
    is($t2->action(), 'Buy', 'action Buy okay');
    is($t2->symbol(), 'VO', 'symbol okay');
    is($t2->symbol(), $t2->ticker()->symbol(),
       'symbol matches ticker');
    is($t2->symbol(), $t2->ticker()->symbol(),
       'symbol matches ticker');
    is($t2->amount(), $t2->shares() * $t2->price() + $t2->commision(),
       'amount was shares*price + commision');

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
    is($t3->date(), '12-31-2010', 'date okay');
    is($t3->action(), 'ReinvDiv', 'action reinvdiv okay');
    is($t3->symbol(), 'VO', 'symbol okay');
    is($t3->symbol(), $t3->ticker()->symbol(),
       'symbol matches ticker');
    is($t3->symbol(), $t3->ticker()->symbol(),
       'symbol matches ticker');
    is($t3->amount(), $t3->shares() * $t3->price() + $t3->commision(),
       'amount was shares*price + commision');
    
    is_deeply($t3->scalarFields, 
	      [ 
		'_account', 
		'_action', 
		'_amount', 
		'_commision', 
		'_date', 
		'_file', 
		'_name', 
		'_price', 
		'_running',
		'_shares', 
		'_symbol', ],
	      'Scalar Fields');

     my $raS = [];
     $t3->printToCsvString(undef, undef, undef, $raS);
     is($raS->[0], ",ReinvDiv,510,10,12-31-2010,,\"VANGUARD MID CAP ETF\",5,,100,VO\n",
        'Formated as CSV');

    # Tickers should be reused.
    is($t2->ticker(), $t3->ticker(), 'tickers are reused');
};

Test::Class->runtests;
