#!/bin/perl

# Methods dealing with an array of transactions

package Transactions;

use Transaction;
use strict;

sub new
{
    my $class = shift;
    my $self = [];
    bless $self, $class;
    return $self;
}

sub newDeepCopy
{
    my ($self) = @_;
    my $copy = Transactions->new();
    foreach my $k ( @{ $self } ) {
	$copy->append($k->newDeepCopy());
    }
    return $copy;
}

sub append
{
    my ($self, $transaction) = @_;
    push @{ $self }, $transaction;
}

sub appendTransactions
{
    my ($self, $transactions) = @_;
    push @{ $self }, @{ $transactions };
}

sub prependTransactions
{
    my ($self, $transactions) = @_;
    unshift @{ $self }, @{ $transactions };
}

sub deleteTransaction
{
    my ($self, $transaction) = @_;
    my $did_something = 0;
    foreach my $i (0 .. scalar(@{$self})-1) {
	if ($transaction == $self->[$i]) {
	    splice(@{$self},$i,1);
	    $did_something = 1;
	}
    }
    if ( ! $did_something ) {
	my @strings;
	$transaction->printToCsvString(\@strings);
	print "Failed to delete transaction: ", join('',@strings);
    }
}

sub printToStringArray
{
    my($self, $raS, $prefix) = @_;
    
    foreach my $k ( @{ $self } ) {
	$k->printToStringArray($raS, $prefix);
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
    
    foreach my $transaction ( @{ $self } ) {
	$transaction->printToCsvString($raS, $raTransCols, $rhNameMap,
				       $csv, $isMstar);
    }
}

sub findTransfersIn
{
    my($self) = @_;
    my $transfers = [];
    foreach my $transaction (@{ $self }) {
	if ($transaction->isTransferIn()) {
	    push @{$transfers}, $transaction;
	}
    }
    return $transfers;
}

sub findMatchingTransferOut
{
    my($self,$transferIn) = @_;
    {
	my $length = scalar(@{ $self });
	my $transaction = $self->[$length - 1];
	if ($transaction->isMatchingTransferOut($transferIn)) {
	    return $transaction;
	}
    }
    foreach my $transaction (@{ $self }) {
	if ($transaction->isMatchingTransferOut($transferIn)) {
	    return $transaction;
	}
    }
    return undef;
}

sub cashFlow
{
    my($self, $rh_cashflow) = @_;

    foreach my $transaction (@{ $self }) {
	$transaction->cashFlow($rh_cashflow);
    }
}

sub computeAllFromTransactions
{
    my($self,$shares,$price,$estimated,$cost_basis,$gain,
       $value,$cash_in,$returned_capital,$my_return,$has_new_trans,
	$rh_cashflow) = @_;

    $$shares = 0;
    $$price = 0 unless defined $$price;
    $$estimated = 0;
    $$cost_basis = 0;
    $$cash_in = 0;
    $$returned_capital = 0;
    
    foreach my $transaction ( @{ $self } ) {
	$transaction->computeAllFromTransactions(
	    $shares,
	    $price,
	    $estimated,
	    $cost_basis,
	    $gain,
	    $value,
	    $cash_in,
	    $returned_capital,
	    $my_return,
	    $rh_cashflow,
	    );
    }
#    printf(STDERR "Total Returned Capital: %f\n", $$returned_capital);

    $$has_new_trans = 0;
}

1;


