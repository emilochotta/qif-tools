#!/bin/perl

# A holding is some number of shares of an asset held in an account.

package Holding;
use Account;
use Ticker;
use Transactions;
use Transaction;
use strict;
use warnings;

#-----------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------

my $gDebug = 1;

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

sub new
{
    my $class = shift;
    my $self = {
	_ticker => shift,        # Ref to Ticker object.

	# Ref to Account object.  May be undef.
	_inAccount => shift,     

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
	_purchases => shift,     # Purchases - Withdrawls
	_myReturn => shift,      # Return = value - _purchases
	_hasNewTrans => shift,   # There are unprocessed transactions
    };
    if ( !defined( $self->{_transactions} )) {
	$self->{_transactions} = Transactions->new();
    } elsif ( ! $self->{_transactions}->isa('Transactions') ) {
	die "Transactions member must be of type \"Transactions\".\n";
    }
    
    bless $self, $class;
    return $self;
}

# Accessors
sub ticker { $_[0]->{_ticker}; }
sub symbol { $_[0]->{_ticker}->symbol(); }
sub inAccount { $_[0]->{_inAccount}; }
sub transactions { $_[0]->{_transactions}; }
sub shares { $_[0]->{_shares}; }
sub price { $_[0]->{_price}; }
sub estimated { $_[0]->{_estimated}; }
sub cost_basis { $_[0]->{_cost_basis}; }
sub gain { $_[0]->{_gain}; }
sub value { $_[0]->{_value}; }
sub purchases { $_[0]->{_purchases}; }
sub myReturn { $_[0]->{_myReturn}; }
sub hasNewTrans { $_[0]->{_hasNewTrans}; }

sub setInAccount { $_[0]->{_inAccount} = $_[1]; }

sub appendTransaction
{
    my ($self, $transaction) = @_;
    $self->{_transactions}->append($transaction);
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
       $raTransCols,   # In: Array of transaction column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $csv,           # In: A CSV object if you want to reuse one.
       $raS,           # Out: Output is written back to this array. 
	) = @_;

    $self->{_transactions}->printToCsvString($raTransCols, $rhNameMap, $csv, $raS);
}

sub print
{
    my($self) = @_;
    my $raS = [];
    $self->printToCsvString(undef, undef, undef, $raS);
    print join("\n", @{$raS}), "\n";
}

sub printToCsvFile
{
    my($self, $fname) = @_;
    my @S;
    open my $io, ">", $fname or die "$fname: $!";
    print "  Writing $fname\n";
    $self->printToCsvString(undef, undef, undef, \@S);
    print $io @S;
    close $io;
}

sub computeAllFromTransactions
{
    my($self) = @_;
    $self->{_transactions}->computeAllFromTransactions(
	\$self->{_shares},
	\$self->{_price},
	\$self->{_estimated},
	\$self->{_cost_basis},
	\$self->{_gain},
	\$self->{_value},
	\$self->{_purchases},
	\$self->{_myReturn},
	\$self->{_hasNewTrans}
    );	
}
1;
