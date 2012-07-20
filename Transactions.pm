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

sub printToStringArray
{
    my($self, $raS, $prefix) = @_;
    
    foreach my $k ( @{ $self } ) {
	$k->printToStringArray($raS, $prefix);
    }
}

sub printToCsv
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
	$transaction->printToCsv($raTransCols, $rhNameMap, $csv, $raS);
    }
}

1;


