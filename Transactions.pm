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

1;


