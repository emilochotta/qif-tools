#!/bin/perl

# A holding is some number of shares of an asset held in an account.

package Holding;
use Transactions;
use strict;

sub new
{
    my $class = shift;
    my $self = {
	_ticker => shift,        # Ref to Ticker object.
	_inAccount => shift,     # Ref to Account object.
	     # Ref to array of Transaction objects (maybe undef)
        _transactions => shift,  
	_shares => shift,        # Current shares
	_price => shift,         # Current price
	_value => shift,         # Current value
    };
    if ( !defined( $self->{_transactions} )) {
	$self->{_transactions} = Transactions->new();
    } elsif ( ! $self->{_transactions}->isa('Transactions') ) {
	die "Transactions member must be of type \"Transactions\".\n";
    }
    
    bless $self, $class;
    return $self;
}

sub appendTransaction
{
    my ($self, $transaction) = @_;
    $self->{_transactions}->append($transaction);
}

sub printToStringArray
{
    my($self, $raS, $prefix) = @_;
    push @{$raS}, sprintf("%sHolding: \"%s\"",
			  $prefix, $self->{_ticker}->symbol() );
    $self->{_transactions}->printToStringArray($raS, $prefix . '  ');
}

1;
