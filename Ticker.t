#!/bin/perl

#
# Test the functionality of Ticker.pm
#
use Ticker;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

sub test_ByName : Test(9) {
    my $t = Ticker::getByName('Vanguard Inflation-Protected Securities Fund Investor Shares');
    ok(defined($t), 'Ticker object was created');
    ok($t->isa('Ticker'), 'Ticker object isa ticker');
    is($t->name(), 'Vanguard Inflation-Protected Securities Fund Investor Shares', 'Ticker name');
    is($t->symbol(), 'VIPSX', 'Ticker symbol');
    is($t->skip(), 1, 'Ticker skip');
    is($t->attribute('Yield'), 2.44, 'Ticker name');

    my $t2 = Ticker::getBySymbol('VIPSX');
    ok(defined($t), 'Ticker object was created');
    ok($t->isa('Ticker'), 'Ticker object isa ticker');
    is($t, $t2, 'Tickers are the same');

#     my $t = Ticker::getByName('VANGUARD REIT');
#     ok(defined($t), 'Ticker object was created');
#     ok($t->isa('Ticker'), 'Ticker object isa ticker');
#     is($t->name(), 'VANGUARD REIT', 'Ticker name');
#     is($t->symbol(), 'VNQ', 'Ticker symbol');
#     is($t->skip(), 0, 'Ticker skip');
#     is($t->attribute('Yield'), 1.36, 'Ticker name');
};

Test::Class->runtests;
