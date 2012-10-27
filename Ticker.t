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
    my $t = Ticker::getByName('DODGE & COX STOCK FUND');
    ok(defined($t), 'Ticker object was created');
    ok($t->isa('Ticker'), 'Ticker object isa ticker');
    is($t->name(), 'DODGE & COX STOCK FUND', 'Ticker name');
    is($t->symbol(), 'DODGX', 'Ticker symbol');
    is($t->skip(), 1, 'Ticker skip');
    is($t->attribute('Yield'), 1.68, 'Ticker name');

    my $t2 = Ticker::getBySymbol('DODGX');
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
