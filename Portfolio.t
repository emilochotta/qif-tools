#!/bin/perl

#
# Test the functionality of Portfolio.pm
#
use Portfolio;
use Account;
use Holding;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# Test basic object creation
sub test_new : Test(2) {
    my $p = new Portfolio();
    ok(defined($p), 'Portfolio object was created');
    ok($p->isa('Portfolio'), 'Portfolio object isa Portfolio');
};

sub test_newFromQuickenSummaryReport : Test(9) {
    my $p = Portfolio::newFromQuickenSummaryReport(
	'test', 'test_portfolio.csv' );
    ok(defined($p), 'Portfolio object was created');
    ok($p->isa('Portfolio'), 'Portfolio object isa Portfolio');

    is($p->name(), 'test', 'Correct Name');
    ok(!defined($p->assetAllocation()), 'No asset allocation');
    is(ref($p->holdings()), 'HASH', 'Holdings are a hash');
    my @a = keys %{$p->holdings()};
    is(scalar(@a), 39, 'Right number of Holdings');
    ok($p->holding('BSV')->isa('Holding'), 'Can Get a Holding');
    is($p->holding('BSV')->shares(), 78.66, 'Right number of shares.');
    ok(!defined($p->accounts()), 'No accounts');
};

sub test_newPortfoliosFromAccounts : Test(12) {
    # Map from portfolio name to list of account names. 
    my %Defs = (
	'all' => [
	    'account1',
	    'account2',
	],
	);
    my %Accts;
    my $a1 = Account::newFromQif('account1', 'account.qif');
    $Accts{$a1->name()} = $a1;
    my $a2 = Account::newFromQif('account2', 'account.qif');
    $Accts{$a2->name()} = $a2;
    my $rhP = Portfolio::newPortfoliosFromAccounts( \%Accts,
						    \%Defs );
    ok(defined($rhP), 'Portfolio object was created');
    is(ref($rhP), 'HASH', 'Portfolios are a hash');
    ok(defined($rhP->{'all'}), '"all" is defined');
    ok($rhP->{'all'}->isa('Portfolio'), '"all" isa Portfolio');
    my $p = $rhP->{'all'};

    is($p->name(), 'all', 'Correct Name');
    ok(!defined($p->assetAllocation()), 'No asset allocation');
    is(ref($p->holdings()), 'HASH', 'Holdings are a hash');
    my @a = keys %{$p->holdings()};
    is(scalar(@a), 4, 'Right number of Holdings');
    ok($p->holding('GLD')->isa('Holding'), 'Can Get a Holding');
    is($p->holding('GLD')->shares(), 190, 'Right number of shares.');
    is(ref($p->accounts()), 'HASH', 'Accounts are a hash');
    @a = keys %{$p->accounts()};
    is(scalar(@a), 2, 'Right number of Accounts');
};

Test::Class->runtests;
