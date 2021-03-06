#!/bin/perl

# A holding is some number of shares of an asset held in an account.

package Holding;
use Account;
use AssetCategory;
use Finance::Math::IRR;
use Ticker;
use Transactions;
use Transaction;
use strict;
use warnings;

#-----------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------

my $gDebug = 1;

# Less than this number of shares is considered a zero balance
my $gZero = 2.0;

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

sub new
{
    my $class = shift;
    my $self = {
	_ticker => shift,        # Ref to Ticker object.

	# Ref to Account.  May be undef.
	_inAccount => shift,     

	# Ref to AssetCategory object.  May be undef.
	_assetCategory => shift,     

	# Ref to array of Transaction objects (will be created if
	# undef)
        _transactions => shift,

	# These may be undef.  They can be recomputed from
	# the transactions using function computeAllFromTransactions.
	_shares => shift,        # Current shares
	_price => shift,         # Current price
	_estimated => shift,     # Some estimated transactios in
				 # Quicken
	_cost_basis => shift,    # Cost basis
	_gain => shift,          # Gain = value - cost_basis
	_value => shift,         # Current value
	_cashIn => shift,        # Purchases - Sales
	_returnedCapital => shift,  # Capital returned (e.g. cash dividend)
	_myReturn => shift,      # Return = value + _returnedCap - _cashIn
	_IRR => shift,           # Internal Rate of Return
	_hasNewTrans => shift,   # There are unprocessed transactions
    };
    if ( defined($self->{_inAccount}) and (ref($self->{_inAccount}) ne 'Account')) {
	die "new Holding, account ref isn't an Account.\n";
    }
    if ( !defined( $self->{_transactions} )) {
	$self->{_transactions} = Transactions->new();
    } elsif ( ! $self->{_transactions}->isa('Transactions') ) {
	die "Transactions member must be of type \"Transactions\".\n";
    }
    
    bless $self, $class;
    return $self;
}

sub newDeepCopy
{
    my ($self) = @_;
    return Holding->new(
	$self->ticker(),
	$self->inAccount(),
	$self->assetCategory(),
	$self->transactions()->newDeepCopy(),
	$self->shares(),
	$self->price(),
	$self->estimated(),
	$self->cost_basis(),
	$self->gain(),
	$self->value(),
	$self->cashIn(),
	$self->returnedCapital(),
	$self->myReturn(),
	$self->IRR(),
	$self->hasNewTrans(),
    );
}

# Accessors
sub ticker { $_[0]->{_ticker}; }
sub symbol { $_[0]->{_ticker}->symbol(); }
sub inAccount { $_[0]->{_inAccount}; }
sub assetCategory { $_[0]->{_assetCategory}; }
sub transactions { $_[0]->{_transactions}; }
sub shares { $_[0]->{_shares}; }
sub price { $_[0]->{_price}; }
sub estimated { $_[0]->{_estimated}; }
sub cost_basis { $_[0]->{_cost_basis}; }
sub gain { $_[0]->{_gain}; }
sub value { $_[0]->{_value}; }
sub cashIn { $_[0]->{_cashIn}; }
sub returnedCapital { $_[0]->{_returnedCapital}; }
sub myReturn { $_[0]->{_myReturn}; }
sub IRR { $_[0]->{_IRR}; }
sub hasNewTrans { $_[0]->{_hasNewTrans}; }

sub setInAccount { $_[0]->{_inAccount} = $_[1]; }
sub setAssetCategory { $_[0]->{_assetCategory} = $_[1]; }
sub setPrice
{
    my($self, $price) = @_;
    $self->{_price} = $price;
    $self->computeAllFromTransactions();
}

sub appendTransaction
{
    my ($self, $transaction) = @_;
    $self->{_transactions}->append($transaction);
}

sub applyTransaction
{
    my ($self, $transaction) = @_;
    if (defined($self->transactions())) {
	$self->{_transactions}->append($transaction);
	$self->computeAllFromTransactions();
    } else {
	my $action = $transaction->action();
	if ($action eq 'Sell') {
	    if (defined($self->shares()) && defined($transaction->shares())) {
		$self->{_shares} -= $transaction->shares();
	    }
	    if (defined($transaction->amount())) {
		$self->{_value} -= $transaction->amount();
	    }
	} elsif ($action eq 'Buy') {
	    if (defined($self->shares()) && defined($transaction->shares())) {
		$self->{_shares} += $transaction->shares();
	    }
	    if (defined($transaction->amount())) {
		$self->{_value} += $transaction->amount();
	    }
	} else {
	    die "Can't handle transaction action $action";
	}
    }
}

sub appendHoldingTransactions
{
    my ($self, $other_holding) = @_;
    if ( !defined($self) ) {
	die "Self isn't defined.\n";
    }
    if ( !defined($other_holding) ) {
	die "other_holding isn't defined.\n";
    }
    if ( ref($other_holding) ne 'Holding') {
	die "other_holding isn't Holding.\n";
    }
    $self->{_transactions}->appendTransactions($other_holding->{_transactions});
    $self->computeAllFromTransactions();
}

sub prependHoldingTransactions
{
    my ($self, $other_holding) = @_;
    if ( !defined($self) ) {
	die "Self isn't defined.\n";
    }
    if ( !defined($other_holding) ) {
	die "other_holding isn't defined.\n";
    }
    if ( ref($other_holding) ne 'Holding') {
	die "other_holding isn't Holding.\n";
    }
    $self->{_transactions}->prependTransactions($other_holding->{_transactions});
    $self->computeAllFromTransactions();
}

sub copyPrice
{
    my($self, $other) = @_;
    $self->setPrice($other->price());
}

sub printToStringArray
{
    my($self, $raS, $prefix, $print_transactions) = @_;
    push @{$raS},
      sprintf("%sHolding: \"%s\"",
	      $prefix, $self->symbol()),
      sprintf("%s  Shares: %.4f",
	      $prefix, $self->{_shares});
    if ($print_transactions) {
	$self->{_transactions}->printToStringArray($raS, $prefix . '  ');
    }
}

sub printToCsvString
{
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $raTransCols,   # In: Array of transaction column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $csv,           # In: A CSV object if you want to reuse one.
       $isMstar,       # In: Apply morningstar rules.
	) = @_;

    $self->{_transactions}->printToCsvString($raS, $raTransCols, $rhNameMap,
					     $csv, $isMstar);
}

sub print
{
    my($self) = @_;
    my $raS = [];
    $self->printToCsvString($raS);
    print join("\n", @{$raS}), "\n";
}

sub printToCsvFile
{
    my($self,
       $fname,
       $raTransCols,   # In: Array of transaction column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       ) = @_;
    my @S;
    open my $io, ">", $fname or die "$fname: $!";
    print "  Writing $fname\n";
    $self->printToCsvString(\@S);
    print $io @S;
    close $io;
}

sub findTransfersIn
{
    my($self) = @_;
    return $self->{_transactions}->findTransfersIn();
}

sub findMatchingTransferOut
{
    my($self,$transferIn) = @_;
    return $self->{_transactions}->findMatchingTransferOut($transferIn);
}

sub prependTransactions
{
    my($self,$transactions) = @_;
    return $self->{_transactions}->prependTransactions($transactions);
}

sub deleteTransaction
{
    my($self,$transaction) = @_;
    return $self->{_transactions}->deleteTransaction($transaction);
}

sub cashFlow
{
    my($self, $rh_cashflow) = @_;
    return $self->{_transactions}->cashFlow($rh_cashflow);
}

sub computeAllFromTransactions
{
    my($self) = @_;

    # Hash with date => transaction-value pairs for the IRR function.
    # A buy is positive and a sell is negative.
    my $rh_cashflow = {};
    
    $self->{_transactions}->computeAllFromTransactions(
	\$self->{_shares},
	\$self->{_price},
	\$self->{_estimated},
	\$self->{_cost_basis},
	\$self->{_gain},
	\$self->{_value},
	\$self->{_cashIn},
	\$self->{_returnedCapital},
	\$self->{_myReturn},
	\$self->{_hasNewTrans},
	$rh_cashflow,
    );
    my $ticker = $self->ticker();
    if (defined($ticker->attribute('Price'))
	&& $ticker->attribute('Price') != 0) {
	$self->{_price} = $ticker->attribute('Price');
    }
    $self->{_value} = $self->{_shares} * $self->{_price};
    my $acct_name = defined($self->inAccount()) ? $self->inAccount()->name() : '';
    ($self->symbol() eq 'LSGLX') && printf("Value of %s in %s is %f * %f = %f\n", $self->symbol(),
					   $acct_name, $self->price(), $self->shares(), $self->value());
    $self->{_gain} = $self->{_value} - $self->{_cost_basis};
    $self->{_myReturn} =
	$self->{_value} + $self->{_returnedCapital} - $self->{_cashIn};

    if ($self->{_value} > $gZero && scalar($self->transactions()) > 0) {
	# Compute IRR.  We need to add a last transaction that represents
	# selling the holding and recouping the value plus any additional
	# money we've made from it.
	my ($yyyy,$mm,$dd) = (localtime)[5,4,3];
	$yyyy += 1900;
	$mm++;
	my $date_string = sprintf("%04d-%02d-%02d", $yyyy, $mm, $dd);
	$rh_cashflow->{$date_string} = -1 * ($self->{_value} + $self->{_returnedCapital});
	printf("Cashflow for %s in %s:\n", $self->symbol(), $acct_name);
	foreach my $date (sort keys %{$rh_cashflow}) {
	    printf("  %s => \$%.2f,\n", $date, $rh_cashflow->{$date});
	}
	$self->{_IRR} = xirr(%{$rh_cashflow}, precision => 0.001);
	if ( defined $self->{_IRR} ) {
	    printf("  xirr for %s in %s is %.2f%%\n", $self->symbol(), $acct_name, 100.0 * $self->{_IRR});
	} else {
	    printf("ERROR: xirr is undefined for %s\n", $self->symbol());
	}
    }
}

1;
