#!/bin/perl

# A transaction is a financial investment transaction like buying or selling an asset.
package Transaction;
use strict;

my $gDebug = 1;

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,
        _symbol => shift,
        _skip  => shift,
        _yield  => shift,
	_assetClass => shift,
	_assetCategory => shift,
    };
    bless $self, $class;
    return $self;
}

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
#   total: Dollar amount of transaction. This is generally the same as amount
#   but in some cases can be higher. (Introduced in Quicken 2005 for windows)
#
# We skip the ones with *

sub newFromQifRecord
{
    my $class = shift;
    my $qif_record = shift;

    if ( $record->{'header'} ne 'Type:Invst' ) {
	&debug("Transaction must be an investment transaction.");
	return undef;
    }
    
    if ( defined($record->{$security}) ) {

	if ( $gDebug ) {
	    print "Record: \n";
	    foreach my $k ( sort keys %{ $record } ) {
		print "  $k = $record->{$k}\n";
	    }
	}

	my $name = $record->{$security};
	$name =~ tr/\r//d;
#		print "Security \"$name\"\n";
	next if ( defined($Skip{$name}) );
	if ( ! defined($Tickers{$name}) ) {
	    if ( !defined($namesSeen{$name}) ) {
		$namesSeen{$name}++;
		print "*** Add the following to \%Tickers or \%Skip\n";
		print "    '", $name, "' => '',\n";
		
	    }
	    next;
	}
	my $ticker = $Tickers{$name};
	if ( ! defined($AssetClass{$ticker}) ) {
	    if ( !defined($namesSeen{$name}) ) {
		$namesSeen{$name}++;
		print "*** Add the following to \%AssetClass\n";
		print "    '", $ticker, "' => \$IntlStock | \$UsStock | \$Bond,\n";
	    }
	}
	$record->{'Ticker'} = $ticker;
	$record->{$security} = $name;
	my $date = &Convert_Qif_Date($record->{'date'});
	$record->{'date'} = $date;
	$record->{'file'} = $basename;

	# Copy the fields to fields keyed by keys that morningstar understands
	foreach my $k ( keys %{ $record } ) {
	    if ( defined $ToMstar{$k} ) {
		$record->{$ToMstar{$k}} = $record->{$k};
	    }
	}

	$record->{'Comm'} = 0 if ( !defined $record->{'Comm'} );

	my $comm = $record->{'Comm'};
	$comm =~ tr/,//d;
	$comm =~ s/\s+$//;
	$record->{'Comm'} = $comm;

	my $price = $record->{'Price'};

	# Use previous price if price undefined
	if (! defined $record->{'Price'} && defined $rhQif->{$ticker}) {
	    my $lastRow = scalar @{$rhQif->{$ticker}} - 1;
	    $price = $rhQif->{$ticker}->[$lastRow]->{'Price'};
	}

	$price =~ tr/,//d;
	$price =~ s/\s+$//;
	$record->{'Price'} = $price;

	if ( defined $record->{'Amount'} ) {
	    my $amount = $record->{'Amount'};
	    $amount =~ tr/,//d;
	    $amount =~ s/\s+$//;
	    $record->{'Amount'} = $amount;
	}

	if ( defined $record->{$Shares} ) {
	    my $shares = $record->{$Shares};
	    $shares =~ tr/,//d;
	    $shares =~ s/\s+$//;
	    $record->{$Shares} = $shares;
	} else {
	    # Calculate shares if unknown
	    if ( defined $record->{'Amount'}
		 && defined $record->{'Price'}
		 && defined $record->{'Comm'} )
	    {
		$record->{$Shares} = ($record->{'Amount'} - $comm) / $price;
	    }
	}

	# There are only 5 actions in morningstar: buy, sell, split, div, reinv
	# We define extra psuedo actions: skip, add
	# OLD comment:
	#    There are only 4 actions in morningstar: buy, sell, split, div
	#    We define extra psuedo actions: skip, cash-div
	# All the 
	my $action = $record->{'Action'};
	$action =~ tr/\r//d;
	if ( defined($Actions{$action}) ) {
	    # $record->{'Action'} = $action = $Actions{$action};
	    $action = $Actions{$action};
	} else {
	    print "Action \"$action\" unknown\n";
	}
	if ( $action eq 'buy' ) {
	    $record->{'Action'} = $action;
	} elsif ( $action eq 'add' ) {
	    if ( defined $TreatAddAsBuy{$ticker} ) {
		printf( "Treating add as buy for \"%s\" on %s\n",
			$ticker, $date);
		$record->{'Action'} = 'buy';
	    } else {
		next;
	    }
	} elsif ( $action eq 'remove' ) {
	    if ( defined $TreatRemoveAsSell{$ticker} ) {
		printf( "Treating remove as sell for \"%s\" on %s\n",
			$ticker, $date);
		$record->{'Action'} = 'sell';
	    } else {
		next;
	    }
	} elsif ( $action eq 'sell' ) {
	    $record->{'Action'} = $action;
	} elsif ( $action eq 'split' ) {
	    if (defined $rhQif->{$ticker}) {
		my $lastRow = scalar @{$rhQif->{$ticker}} - 1;
		$record->{'Price'} = $rhQif->{$ticker}->[$lastRow]->{'Price'};
	    }
	    $record->{'Amount'} = 0;
	    $record->{'Action'} = $action;
	    if ( defined( $Splits{$ticker}{$date} ) ) {
		$record->{$Shares} = $Splits{$ticker}{$date};
	    } else {
		printf( "WARNING: No split info for \"%s\" on %s\n",
			$ticker, $date);
	    }

	} elsif ( $action eq 'div' ) {
	    $record->{'Action'} = $action;
	} elsif ( $action eq 'reinv' ) {
	    $record->{'Action'} = $action;
	} elsif ( $action eq 'skip' ) {
	    next;
	    
	} elsif ( $action eq 'cash-div' ) {
	    # This is the tricky one
	    # Record a cash dividend as a
	    # reinvDiv followed by a sale
	    my $shares = $record->{$Shares};

	    my $rhCopy = {};
	    foreach my $k ( keys %{ $record } ) {
		$rhCopy->{$k} = $record->{$k};
	    }

	    $rhCopy->{'Action'} = 'div';
	    $record->{'Action'} = 'sell';
	    push @{$rhQif->{$ticker}}, $rhCopy;

	} elsif ( $action eq 'reinv-div' ) {
	    # This is the tricky one
	    # Record a reinvest dividend as a
	    # reinvDiv followed by a buy
	    my $shares = $record->{$Shares};
	    my $price;

	    my $rhCopy = {};
	    foreach my $k ( keys %{ $record } ) {
		$rhCopy->{$k} = $record->{$k};
	    }

	    $rhCopy->{'Action'} = 'div';
	    $record->{'Action'} = 'buy';
	    push @{$rhQif->{$ticker}}, $rhCopy;
	} else {
	    if ( !defined($rhActionsSeen->{$action}) ) {
		$rhActionsSeen->{$action}++;
		print "'", $action, "' => '',\n";
	    }
	}

# 		print "Processed:\n";
# 		foreach my $k ( sort keys %{ $record } ) {
# 		    print "  $k = $record->{$k}\n";
# 		}

	push @{$rhQif->{$ticker}}, $record;
    }
}

1;

