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
       $raTransCols,   # In: Array of transaction column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $csv,           # In: A CSV object if you want to reuse one.
       $raS,           # Out: Output is written back to this array. 
	) = @_;
    
    foreach my $transaction ( @{ $self } ) {
	$transaction->printToCsvString($raTransCols, $rhNameMap, $csv, $raS);
    }
}

sub computeAllFromTransactions
{
    my($self,$shares,$price,$estimated,$cost_basis,$gain,
       $value,$purchases,$my_return,$has_new_trans) = @_;

    $$shares = 0;
    $$price = 0;
    $$estimated = 0;
    $$cost_basis = 0;
    $$gain = 0;
    $$value = 0;
    $$purchases = 0;
    $$my_return = 0;
    
    foreach my $transaction ( @{ $self } ) {
	$transaction->computeAllFromTransactions(
	    $shares,
	    $price,
	    $estimated,
	    $cost_basis,
	    $gain,
	    $value,
	    $purchases,
	    $my_return,
	    );
    }

    $$has_new_trans = 0;
}

1;


