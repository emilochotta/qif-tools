#!/bin/perl

# A rebalance Transaction is a transaction paired with the Portfolio
# that it generates.

package RebalTran;
use Transaction;
use Time::Format qw(%time time_format);
use strict;
use warnings;

#-----------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------

my $gDebug = 1;

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

sub new {
    my $class = shift;
    my $self = {
	_transaction => shift,   # Must be defined
	_portfolio => shift,     # Must be defined
    };
    bless $self, $class;
    return $self;
}

sub transaction { $_[0]->{_transaction}; }
sub portfolio { $_[0]->{_portfolio}; }

sub newCommon {
    my (
	$reason,
	$action,
	$name,
	$ticker,
	$symbol,
	$account_name,
	$price,
	$shares,
	$portfolio,
	) = @_;

    return RebalTran->new(
      Transaction::new(
	  $time{'mm-dd-yyyy'},
	  $action,
	  $name,
	  $ticker,
	  $symbol,
	  $account_name,
	  $price,
	  $shares,
	),
	$portfolio);
}

sub newSale {
    my (
	$reason,
	$name,
	$ticker,
	$symbol,
	$account_name,
	$price,
	$shares,
	$portfolio,
	) = @_;
    return RebalTran::newCommon(
	$reason,
	'Sell',
	$name,
	$ticker,
	$symbol,
	$account_name,
	$price,
	$shares,
	$portfolio,
	);
}

1;
