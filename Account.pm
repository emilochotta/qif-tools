#!/bin/perl

# An account represents an investment account that can contain
# multiple assets.
package Account;

use Holding;
use Transaction;
use Finance::QIF;
use strict;

my $gDebug = 1;

sub new
{
    my $class = shift;
    my $self = { 
	_name => shift,         # Must be defined
	_taxable => shift,      
        _holdings  => shift,    # hash keyed by holding symbol
	_qif_filename => shift,
    };
    bless $self, $class;
    return $self;
}

sub newFromQif
{
    my ($name, $taxable, $qif_filename) = @_;

    $gDebug && print("Read Account from $qif_filename: \n");
    my $qif = Finance::QIF->new( file => $qif_filename );

    my $holdings = {};
    my $self = Account->new(
	$name,
	$taxable,
	$holdings,
	$qif_filename,
	);

    while ( my $record = $qif->next ) {
	my $transaction = Transaction::newFromQifRecord($record);
	if (defined($transaction)) {
	    my $symbol = $transaction->symbol();
	    if (!defined( $holdings->{ $transaction->symbol() } )) {
		$holdings->{ $symbol } = Holding->new(
		    $transaction->ticker(),
		    $self);
	    }
	    $holdings->{ $symbol }->appendTransaction($transaction);
	}
    }
    
    return $self;
}

sub printToStringArray
{
    my($self, $raS, $prefix) = @_;
    push @{$raS}, sprintf("%sAccount: \"%s\"",
			  $prefix,
			  $self->{_name});
    push @{$raS}, sprintf("%s  Taxable: \"%s\"",
			  $prefix,
			  defined($self->{_taxable})
			  ? sprintf("%d",$self->{_taxable})
			  : 'undef');
    foreach my $symbol ( sort keys %{ $self->{_holdings} } ) {
	$self->{_holdings}->{$symbol}->printToStringArray($raS,
	    $prefix . '  ');
    }
}
    
1;
