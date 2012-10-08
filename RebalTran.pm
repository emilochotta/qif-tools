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
	_reason => shift,        # May be undef
    };
    if (ref($self->{_transaction}) ne 'Transaction') {
	print "ERROR: First argument to RebalTran my be a Transaction.";
    }
    if (ref($self->{_portfolio}) ne 'Portfolio') {
	print "ERROR: _portfolio argument to RebalTran must be a Portfolio.";
    }
    bless $self, $class;
    return $self;
}

sub transaction { $_[0]->{_transaction}; }
sub portfolio { $_[0]->{_portfolio}; }
sub reason { $_[0]->{_reason}; }

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

    if (ref($ticker) ne 'Ticker') {
	print "ERROR: $ticker argument to RebalTran::newCommon must be a Ticker.\n";
    }
    my $transaction = Transaction->new(
	$time{'mm-dd-yyyy'},
	$action,
	$name,
	$ticker,
	$symbol,
	$account_name,
	$price,
	$shares,
	0,                 # commision
	$shares * $price,  # amount
	);
    return RebalTran->new($transaction, $portfolio, $reason);
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
    if (ref($ticker) ne 'Ticker') {
	print "ERROR: $ticker argument to RebalTran::newSale must be a Ticker.\n";
    }
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

sub newBuy {
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
    if (ref($ticker) ne 'Ticker') {
	print "ERROR: $ticker argument to RebalTran::newSale must be a Ticker.\n";
    }
    return RebalTran::newCommon(
	$reason,
	'Buy',
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
