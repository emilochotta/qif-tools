#!/bin/perl

# A transaction is a financial investment transaction like buying or
# selling an asset.

package Transaction;

use Finance::QIF;
use Ticker qw($gCash);
use strict;

my $gDebug = 1;

# Supported quick action types
my %Actions = (
    'Buy' => 1,
    'BuyX' => 1,
    'Cash' => 1,
    'CGLong' => 1,
    'CGLongX' => 1,
    'CGShort' => 1,
    'CGShortX' => 1,
    'Div' => 1,
    'DivX' => 1,
    'MiscExpX' => 1,
    'ReinvDiv' => 1,
    'ReinvLg' => 1,
    'ReinvSh' => 1,
    'SellX' => 1,
    'ShrsIn' => 1,
    'ShrsOut' => 1,
    'StkSplit' => 1,
    'Sell' => 1,
    );

sub new
{
    my $class = shift;
    my $self = {
	_date => shift,       # Must be defined
	_action => shift,     # Must be defined
	_name => shift,       # Must be defined
	_ticker => shift,     # Must be defined
	_price => shift,
	_shares => shift,
	_commision => shift,
	_amount => shift,
    };
    bless $self, $class;
    return $self;
}

#
# From the docs for Finance::QIF for Type:Invst
#   This is for Investment ledger transactions. The following values are supported for this record type.
#   date: Date of transaction.
#   action: Type of transaction like buy, sell, ...
#   security: Security name of transaction.
#   price: Price of security at time of transaction.
#   quantity: Number of shares purchased.
#   transaction: Cost of shares in transaction.
#   * status: Reconciliation status of transaction.
#   * text: Text for non security specific transaction.
#   * memo: Additional text describing transaction.
#   commission: Commission fees related to transaction.
#   account: Account related to security specific transaction.
#   amount: Dollar amount of transaction.
#   total: Dollar amount of transaction. This is generally the
#     same as amount but in some cases can be higher.
#     (Introduced in Quicken 2005 for windows)
#
# We skip the ones with *

sub newFromQifRecord
{
    my $record = shift;

    $gDebug && print("Record: \n");
    foreach my $k ( sort keys %{ $record } ) {
	$record->{$k} =~ tr/\r\n,//d;
	$record->{$k} =~ s/\s+$//;
	$gDebug && print "  $k = $record->{$k}\n";
    }

    if ( $record->{'header'} ne 'Type:Invst' ) {
	$gDebug && print("Transaction isn't an investment transaction.\n");
	return undef;
    }
#    Record: 
#      action = Buy
#      date = 11/ 8'10
#      header = Type:Invst
#      memo = BUY
#      price = 71.1984
#      quantity = 120
#      security = VANGUARD MID CAP ETF
#      status = R
#      total = 8543.80
#      transaction = 8543.80

    my $date;
    my $action;
    my $name;
    my $ticker;
    my $price;
    my $shares;
    my $commision;
    my $amount;
    
    $date = &ConvertQifDate($record->{'date'});
    $action = $record->{'action'};
    if ( !defined($Actions{$action}) ) {
	die "Action \"$action\" unknown\n";
    }
    $amount = $record->{'total'} if defined $record->{'total'};

    if ( $action eq 'Cash' ) {
	$name = $Ticker::gCash;
	$price = 1.0;
	$shares = $amount if defined($amount);
    } else {
	if ( !defined($record->{'security'}) ) {
	    $gDebug && print("Transaction has no security name.\n");
	    return undef;
	}
	$name = $record->{'security'};
	$price = $record->{'price'} if
	    defined $record->{'price'};
	$shares = $record->{'quantity'} if
	    defined $record->{'quantity'};
    }
    $gDebug && print("Name \"$name\".\n");
    $ticker = Ticker::getByName($name);

    # Don't create transactions for ticker types marked
    # "Skip".
    $commision = 0;
    $commision = $record->{'Comm'} if defined $record->{'Comm'};
    
    return Transaction->new(
	$date,
	$action,
	$name,
	$ticker,
	$price,
	$shares,
	$commision,
	$amount);
}

sub ConvertQifDate {
    my $date = shift;
    $date =~ tr/\"\r\n//d;
    $date =~ s/\s*(\d+)\/\s*(\d+)'1(\d)/$1-$2-201$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)' (\d)/$1-$2-200$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)\/(\d+)/$1-$2-19$3/;
    return $date;
}

sub ticker
{
    my ($self) = @_;
    return $self->{_ticker};
}

sub printToStringArray
{
    my($self, $raS, $prefix) = @_;
    
    push @{$raS}, sprintf("%s\"Transaction\"", $prefix);
    foreach my $k ( sort keys %{ $self } ) {
	push @{$raS}, sprintf("%s  \"%s\": \"%s\"",
			      $prefix, $k, $self->{$k});
	if (ref($self->{$k}) eq 'Ticker') {
	    $self->{$k}->printToStringArray($raS, $prefix . '  ');
	}
    }
}

sub symbol
{
    my ($self) = @_;
    if (!defined($self->{_ticker})) {
	my $raString = [];
	print join("\n", $self->printToStringArray($raString, ''));
	die('Ticker must be defined.');
    }
    return $self->{_ticker}->symbol();
}

1;

