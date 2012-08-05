#!/bin/perl

# A transaction is a financial investment transaction like buying or
# selling an asset.

package Transaction;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(@MstarHeaders %MstarMap $gAccount);

use Finance::QIF;
use Text::CSV_XS;
use Ticker qw($kCash);
use Util;
use strict;

#-----------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------

my $gDebug = 0;

# These are headers in the CSV file that morningstar import
# understands.  They are in an array so that order is preserved.
our @MstarHeaders = (
    'Ticker',
    'File',
    'Date',
    'Action',
    'Name',
    'Price',
    'Shares/Ratio',
    'Comm',
    'Amount',
    'Running'
    );

# Map from morningstar fields to Transaction object fields.
our %MstarMap = (
    'Ticker' => '_symbol',
    'File' => '_file',
    'Date' => '_date',
    'Action' => '_action',
    'Name' => '_name',
    'Price' => '_price',
    'Shares/Ratio' => '_shares',
    'Comm' => '_commision',
    'Amount' => '_amount',
    'Running' => '_running',
    );

# Supported quicken fields
my %QifFields = (
    'account' => 1,
    'action' => 1,
    'amount' => 1,
    'category' => 1,
    'commission' => 1,
    'date' => 1,
    'header' => 1,
    'memo' => 1,
    'number' => 1,
    'payee' => 1,
    'price' => 1,
    'quantity' => 1,
    'security' => 1,
    'splits' => 1,
    'status' => 1,
    'text' => 1,
    'total' => 1,
    'transaction' => 1,
    );

# Supported quicken action types.
our %Actions = (
    'Buy' => 1,
    'BuyX' => 1,
    'Cash' => 1,
    'CGLong' => 1,
    'CGLongX' => 1,
    'CGShort' => 1,
    'CGShortX' => 1,
    'ContribX' => 1,
    'CvrShrt' => 1,
    'Div' => 1,
    'DivX' => 1,
    'Exercise' => 1,
    'Expire' => 1,
    'Grant' => 1,
    'IntInc' => 1,
    'MargInt' => 1,
    'MiscExpX' => 1,
    'ReinvDiv' => 1,
    'ReinvLg' => 1,
    'ReinvSh' => 1,
    'SellX' => 1,
    'ShrsIn' => 1,
    'ShrsOut' => 1,
    'ShtSell' => 1,
    'StkSplit' => 1,
    'Sell' => 1,
    'Vest' => 1,
    'WithdrwX' => 1,
    'XIn' => 1,
    'XOut' => 1,
    );

#-----------------------------------------------------------------
# Global Variables with File Scope
#-----------------------------------------------------------------

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

sub new
{
    my $class = shift;
    my $self = {
	_date => shift,       # Must be defined
	_action => shift,     # Must be defined
	_name => shift,       # Must be defined
	_ticker => shift,     # Must be defined
	_symbol => shift,     # Must be defined
	_account => shift,    # Account name
	_price => shift,
	_shares => shift,
	_commision => shift,
	_amount => shift,
	_file => shift,
	_running => shift,
    };
    bless $self, $class;
    return $self;
}

sub newDeepCopy
{
    my ($self) = @_;
    my $copy = Transaction->new();
    foreach my $k ( sort keys %{ $self } ) {
	# Don't use the deepcopy here because tickers are read only
	# shared data, and that's the only object data member.
	$copy->{$k} = $self->{$k};
    }
    return $copy;
}

sub date { $_[0]->{_date}; }
sub action { $_[0]->{_action}; }
sub name { $_[0]->{_name}; }
sub ticker { $_[0]->{_ticker}; }
sub symbol { $_[0]->{_symbol}; }
sub account { $_[0]->{_account}; }
sub price { $_[0]->{_price}; }
sub shares { $_[0]->{_shares}; }
sub commision { $_[0]->{_commision}; }
sub amount { $_[0]->{_amount}; }
sub file { $_[0]->{_file}; }
sub running { $_[0]->{_running}; }

sub setAccount { $_[0]->{_account} = $_[1]; }

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
	if ( !defined($QifFields{$k}) ) {
	    die "QIF Field \"$k\" unknown\n";
	}
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
    my $account;
    my $price;
    my $shares;
    my $commission;
    my $amount;
    
    $date = &ConvertQifDate($record->{'date'});
    $action = $record->{'action'};
    if ( !defined($Actions{$action}) ) {
	die "Action \"$action\" unknown\n";
    }
    if (defined($record->{'total'}) && defined($record->{'transaction'})) {
	if ( $record->{'total'} != $record->{'transaction'} ) {
	    die "Date: \"\": Transaction != Total\n";
	}
	$amount = $record->{'total'};
    } elsif (defined $record->{'total'}) {
	$amount = $record->{'total'};
    } elsif (defined $record->{'transaction'}) {
	$amount = $record->{'transaction'};

# Removed this check because it skipped shrs added transactions
#     } else {
# 	# Transaction without some kind of total isn't useful.
# 	$gDebug && print("Transaction must have total or transaction.\n");
# 	return undef;
    }

    if ( $action eq 'Cash' ) {
	return undef unless defined($amount);
	$name = $Ticker::kCash;
	$price = 1.0;
	$shares = $amount;
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

    # An unknown name will raise an exception, which is what we want.
    # A ticker marked as "skip" will still be processed.
    $ticker = Ticker::getByName($name);

    $commission = 0;
    $commission = $record->{'commission'} if defined $record->{'commission'};
    
    $account = $record->{'account'} if defined $record->{'account'};
    
    return Transaction->new(
	$date,
	$action,
	$name,
	$ticker,
	$ticker->symbol(),
	$account,
	$price,
	$shares,
	$commission,
	$amount);
}

sub ConvertQifDate
{
    my $date = shift;
    $date =~ tr/\"\r\n//d;
    $date =~ s/\s*(\d+)\/\s*(\d+)'1(\d)/$1-$2-201$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)' (\d)/$1-$2-200$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)\/(\d+)/$1-$2-19$3/;
    return $date;
}

# Returns a ref to an array.
sub scalarFields
{
    my($self) = @_;
    my $f = [];
    foreach my $k ( sort keys %{ $self } ) {
	# Include only fields that are scalar
	push @{ $f }, $k if (ref($self->{$k}) eq '');
    }
    return $f;
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

sub print
{
    my($self) = @_;
    my $raS = [];
    $self->printToCsvString(undef, undef, undef, $raS);
    print join("\n", @{$raS}), "\n";
}

sub printToCsvString
{
    my($self, 
       $raFieldNames,  # In: Array of column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $csv,           # In: A CSV object if you want to reuse one.
       $raS,           # Out: Output is written back to this array. 
	) = @_;
    
    $raFieldNames = $self->scalarFields() unless defined $raFieldNames;
    $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ }) unless defined $csv;
    Util::printHashToCsv($self, $raFieldNames, $rhNameMap, $csv, $raS);
}

sub computeAllFromTransactions
{
    my($self,$shares,$price,$estimated,$cost_basis,$gain,
       $value,$purchases,$my_return) = @_;

    my $action = $self->{_action};

    if ($action eq 'Buy') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'BuyX') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'Cash') {
    } elsif ($action eq 'CGLong') {
    } elsif ($action eq 'CGLongX') {
    } elsif ($action eq 'CGShort') {
    } elsif ($action eq 'CGShortX') {
    } elsif ($action eq 'ContribX') {
    } elsif ($action eq 'CvrShrt') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'Div') {
    } elsif ($action eq 'DivX') {
    } elsif ($action eq 'Exercise') {
    } elsif ($action eq 'Expire') {
    } elsif ($action eq 'Grant') {
    } elsif ($action eq 'IntInc') {
    } elsif ($action eq 'MargInt') {
    } elsif ($action eq 'MiscExpX') {
    } elsif ($action eq 'ReinvDiv') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'ReinvLg') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'ReinvSh') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'SellX') {
	$$shares -= $self->{_shares};
    } elsif ($action eq 'ShrsIn') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'ShrsOut') {
	$$shares -= $self->{_shares};
    } elsif ($action eq 'ShtSell') {
	$$shares -= $self->{_shares};
    } elsif ($action eq 'StkSplit') {
	die "Action \"$action\" NOT SUPPORTED\n";
    } elsif ($action eq 'Sell') {
	$$shares -= $self->{_shares};
    } elsif ($action eq 'Vest') {
    } elsif ($action eq 'WithdrwX') {
    } elsif ($action eq 'XIn') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'XOut') {
	$$shares -= $self->{_shares};
    } else {
	die "Action \"$action\" unknown\n";
    }
    $gDebug && print("Action \"$action\", Shares \"$$shares\".\n");
}

1;

