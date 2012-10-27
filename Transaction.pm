#!/bin/perl

# A transaction is a financial investment transaction like buying or
# selling an asset.

package Transaction;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(@MstarHeaders %MstarMap $gAccount &scalarFields);

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
    'Account',
    'Date',
    'Action',
    'Name',
    'Price',
    'Shares/Ratio',
    'Comm',
    'Amount',
    );

# Map from morningstar fields to Transaction object fields.
our %MstarMap = (
    'Ticker' => '_symbol',
    'Account' => '_account',
    'Date' => '_date',
    'Action' => '_mAction',
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

# Supported quicken action types.  Map also shows equivalent
# morningstar actions.
our %Actions = (
    'Buy' => 'Buy',
    'BuyX' => 'Buy',
    'Cash' => '',
    'CGLong' => 'CGLong',
    'CGLongX' => 'CGLongX',
    'CGShort' => 'CGShort',
    'CGShortX' => 'CGShortX',
    'ContribX' => '',
    'CvrShrt' => 'CvrShrt',
    'CvrShrtX' => 'CvrShrt',
    'Div' => 'Div',
    'DivX' => 'Div',
    'Exercise' => 'Exercise',
    'Expire' => '',
    'Grant' => '',
    'IntInc' => 'IntInc',
    'IntIncX' => 'IntInc',
    'MargInt' => 'MargInt',
    'MargIntX' => 'MargInt',
    'MiscExpX' => 'MiscExpX',
    'MiscIncX' => 'MiscIncX',
    'ReinvDiv' => 'ReinvDiv',
    'ReinvLg' => 'ReinvLg',
    'ReinvSh' => 'ReinvSh',
    'SellX' => 'Sell',
    'ShrsIn' => 'ShrsIn',
    'ShrsOut' => 'ShrsOut',
    'ShtSell' => 'ShtSell',
    'ShtSellX' => 'ShtSell',
    'StkSplit' => 'StkSplit',
    'Sell' => 'Sell',
    'Vest' => '',
    'WithdrwX' => '',
    'XIn' => 'XIn',
    'XOut' => 'XOut',
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
	_account => shift,    # Account name in which this transaction
			      # was found. May be undefined.
	_price => shift,
	_shares => shift,
	_commision => shift,
	_amount => shift,
	_mAction => shift,    # Morningstar equivalent action
	_age => shift,        # Days since 2000-Jan-01
	_totalShares => shift,  # Running total of shares in this Holding
    };
    if (defined($self->{_date}) && ref($self->{_ticker}) ne 'Ticker') {
	print "ERROR: _ticker argument to Transaction must be a Ticker.\n";
	printf("  _date = %s\n", $self->{_date});
	printf("  _action = %s\n", $self->{_action});
	printf("  _name = %s\n", $self->{_name});
	printf("  _symbol = %s\n", $self->{_symbol});
    }

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
sub age { $_[0]->{_age}; }
sub totalShares { $_[0]->{_totalShares}; }
sub mAction { $_[0]->{_mAction}; }

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
    my ($record, $account) = @_;

    # $gDebug = 1 if ($account eq 'schwab-emil');

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
    my $age;
    my $action;
    my $name;
    my $ticker;
    my $price;
    my $shares;
    my $commission;
    my $amount;
    my $mAction;
    
    $date = &ConvertQifDate($record->{'date'});
    $age = &DateToDaysSince2000($date);
    $action = $record->{'action'};
    if ( !defined($Actions{$action}) ) {
	die "Action \"$action\" unknown\n";
    }
    $mAction = $Actions{$action};
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
	if ( ($action eq 'ShrsIn' || $action eq 'ShrsInX') &&
	     !defined($record->{'quantity'}) ) {
	    $gDebug && print("ShrsIn Transaction has no shares.\n");
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
    
    $gDebug = 0 if ($account eq 'schwab-emil');

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
	$amount,
	$mAction,
	$age,
	0);
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
    $self->printToCsvString($raS);
    print join("\n", @{$raS}), "\n";
}

sub printToCsvString
{
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $raFieldNames,  # In: Array of column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $csv,           # In: A CSV object if you want to reuse one.
       $isMstar,       # In: Apply morningstar rules.
	) = @_;

    $isMstar = 0 unless defined $isMstar;
    my $skip = $self->ticker()->skip()
	|| ($isMstar && $self->shares() == 0)
	|| ($isMstar && $self->mAction() eq '');
    if (!$skip) {
	$raFieldNames = $self->scalarFields() unless defined $raFieldNames;
	$csv = Text::CSV_XS->new ({ binary => 1, eol => $/ }) unless defined $csv;
	Util::printHashToCsv($self, $raFieldNames, $rhNameMap, $csv, $raS);
    }
}

sub isTransferIn
{
    my($self) = @_;
    return 0 if ($self->ticker()->skip());
    return ($self->{_action} eq 'ShrsIn') || ($self->{_action} eq 'XIn');
}

sub isMatchingTransferOut
{
    my($self,$transferIn) = @_;
    return 0 if ($self->ticker()->skip());
    return 0 unless ($self->{_action} eq 'ShrsOut' || $self->{_action} eq 'XOut');
    # Date has to be less than 2 weeks apart
    return 0 unless (abs($self->age() - $transferIn->age()) < 14);
    return 0 unless ($self->shares() == $transferIn->shares());
    return 1;
}

sub cashFlow
{
    my($self,
       $rh_cashflow) = @_;
    return if ($self->ticker()->skip());
    my $action = $self->{_action};
    
    if ($action eq 'Buy' || $action eq 'BuyX'
	|| $action eq 'CvrShrt' || $action eq 'CvrShrtX') {
	my $date = &ReformatDateForIRR($self->date());
	my $irr_amount = $self->{_amount};
	if (defined $rh_cashflow->{$date}) {
	    $rh_cashflow->{$date} += $irr_amount;
	} else {
	    $rh_cashflow->{$date} = $irr_amount;
	}
    } elsif ($action eq 'Sell'
	     || $action eq 'SellX'
	     || $action eq 'ShtSell'
	     || $action eq 'ShtSellX'
	) {
	my $date = &ReformatDateForIRR($self->date());
	my $irr_amount = -1 * $self->{_amount};
	if (defined $rh_cashflow->{$date}) {
	    $rh_cashflow->{$date} += $irr_amount;
	} else {
	    $rh_cashflow->{$date} = $irr_amount;
	}
    }
}

sub computeAllFromTransactions
{
    # Compute shares, cost_basis, cash_in, returned_capital
    my($self,$shares,$price,$estimated,$cost_basis,$gain,
       $value,$cash_in,$returned_capital,$my_return,
	$rh_cashflow) = @_;

    return if ($self->ticker()->skip());
    my $action = $self->{_action};

    if ($action eq 'Buy' || $action eq 'BuyX'
	|| $action eq 'CvrShrt' || $action eq 'CvrShrtX') {
	$$shares += $self->{_shares};
	$$cost_basis += $self->{_amount};
	$$cash_in += $self->{_amount};
	$gDebug && printf("      Buy: %f Shares, total cost(\$%f) => %f Shares\n",
	       $self->{_shares}, $self->{_amount}, $$shares, );
 	($self->symbol() eq 'LSGLX') && printf("      Buy: %f Shares, total cost(\$%f) => %f Shares\n",
 	       $self->{_shares}, $self->{_amount}, $$shares, );
    } elsif ($action eq 'Cash'
	     || $action eq 'ContribX'
	     ) {
	# TODO: Figure out what to do with cash transactions.
    } elsif ($action eq 'CGLong' || $action eq 'CGLongX' ||
	     $action eq 'CGShort' || $action eq 'CGShortX' ||
	     $action eq 'Div' || $action eq 'DivX' ||
	     $action eq 'IntInc' || $action eq 'IntIncX' ||
	     $action eq 'MiscIncX' ) {
	$$returned_capital += $self->{_amount};
# 	printf(STDERR "Returned Capital: %s %s %s %f %f\n", $self->account(),
# 	       $self->date(), $self->symbol(), $self->amount(),
# 	       $$returned_capital);
    } elsif ($action eq 'ReinvDiv'
	     || $action eq 'ReinvLg'
	     || $action eq 'ReinvSh') {
	$$shares += $self->{_shares};
	$$cost_basis += $self->{_amount};
    } elsif ($action eq 'Sell'
	     || $action eq 'SellX'
	     || $action eq 'ShtSell'
	     || $action eq 'ShtSellX'
	) {

	my $avg_cost;
	if ($$shares > 0) {
	    # This implements avg cost basis.
	    $avg_cost = $$cost_basis / $$shares;
	} else {
	    print "SALE when there are no shares to sell";
	    $self->print();
	    die "SALE when there are no shares to sell";
	}

	$$cost_basis -= ($avg_cost * $self->{_shares});
	$$cash_in -= $self->{_amount};
	$$shares -= $self->{_shares};
	$gDebug && printf("      Sell: %f Shares, total value(\$%f) => %f Shares\n",
	       $self->{_shares}, $self->{_amount}, $$shares, );
 	($self->symbol() eq 'LSGLX') && printf("      Sell: %f Shares, total cost(\$%f) => %f Shares\n",
 	       $self->{_shares}, $self->{_amount}, $$shares, );
    } elsif ($action eq 'ShrsIn'
	     || $action eq 'XIn') {
	$$shares += $self->{_shares};
    } elsif ($action eq 'ShrsOut'
	     || $action eq 'XOut') {
	$$shares -= $self->{_shares};
    } elsif ($action eq 'Exercise'
	     || $action eq 'Expire'
	     || $action eq 'Vest'
	     || $action eq 'Grant'
	     || $action eq 'MargInt'
	     || $action eq 'MargIntX'
	     || $action eq 'MiscExpX'
	) {
	# Noop
#    } elsif ($action eq 'StkSplit'
# 	|| $action eq 'WithdrwX'
# 	|| $action eq 'MargInt'
    } else {
	die "Action \"$action\" NOT SUPPORTED in ComputeAllFromTransactions\n";
    }
#    $gDebug && print("Action \"$action\", Shares \"$$shares\".\n");

    $self->cashFlow($rh_cashflow);
}

sub DateToDaysSince2000 {
    my $date = shift;
    my ($mm,$dd,$yyyy) = ($date =~ /(\d+)-(\d+)-(\d+)/);

   my %DaysPerMonth = (
    '1' => 31,
    '2' => 28, # will need leap year correction
    '3' => 31,
    '4' => 30,
    '5' => 31,
    '6' => 30,
    '7' => 31,
    '8' => 31,
    '9' => 30,
    '10' => 31,
    '11' => 30,
    '12' => 31,
    );

 #   print $date, "-> mm = $mm, dd = $dd, yyyy = $yyyy  ==> ";
    my $age = 0;
    foreach my $y ( 2000 .. $yyyy ) {
	$age += 365;
	$age++ if ( &IsLeap($y) );
    }
    foreach my $m ( 1 .. $mm ) {
	$age += $DaysPerMonth{$m};
    }
    $age += $dd;
    return $age;
}

sub IsLeap {
    my $y = shift;    # year
    return 0 if ( $y % 4 != 0 ); # Leap years are divisible by 4
    return 1 if ( $y % 400 == 0 ); # Any year divisible by 400 is a leap year
    return 0 if ( $y % 100 == 0 ); # Divisible by 100 (but not 400) isn't a leap year
    return 1;
}

sub ReformatDateForIRR {
    my $date = shift;
    my ($mm,$dd,$yyyy) = ($date =~ /(\d+)-(\d+)-(\d+)/);
    return sprintf("%04d-%02d-%02d", $yyyy, $mm, $dd);
}
1;

