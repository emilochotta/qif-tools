#!/bin/perl

# An account represents an investment account that can contain
# multiple assets.
package Account;

use Holding;
use Finance::QIF;
use strict;

#-----------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------

my $gDebug = 1;

#-----------------------------------------------------------------
# Global Variables with File Scope
#-----------------------------------------------------------------

my $gAccountsByName = {};

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

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
    $gAccountsByName->{$self->{_name}} = $self;
    return $self;
}

sub name { $_[0]->{_name}; }
sub taxable { $_[0]->{_taxable}; }
sub holdings { $_[0]->{_holdings}; }
sub holding { $_[0]->{_holdings}->{$_[1]}; }
sub qif_filename { $_[0]->{_qif_filename}; }

sub newAccountsFromQifDir {
    my ($dir) = @_;

    opendir(DIR, $dir) || die "can't opendir $dir: $!";
    foreach my $file (readdir (DIR) ) {
	next unless $file =~ /^(.*)\.qif$/i;
	my $base = $1;
	print "Reading File: ", $file, ":\n";
	&newFromQif($base, "$dir/$file");
    }
    closedir DIR;
    return $gAccountsByName;
}

# Note that the "account" field in a QIF file doesn't tell you which
# account this transaction is from.  The only way to know the account
# name is to specify it.
sub newFromQif
{
    my ($account_name, $qif_filename, $taxable) = @_;

    $gDebug && print("Read Account from $qif_filename: \n");
    my $qif = Finance::QIF->new( file => $qif_filename );

    # Create a new account if needed.  If the account already exists,
    # the new transactions will be appended to it.
    my $account;
    my $holdings;
    if (defined($gAccountsByName->{$account_name})) {
	$account = $gAccountsByName->{$account_name};
	$holdings = $account->{_holdings};
    } else {
	$gDebug && print("Creating new account $account_name\n");
	$holdings = {};
	$account = Account->new(
	    $account_name,
	    $taxable,
	    $holdings,
	    $qif_filename,
	    );
    }

    while ( my $record = $qif->next ) {
	my $transaction = Transaction::newFromQifRecord($record);
	if (defined($transaction)) {

	    # Create a new holding if needed.
	    my $symbol = $transaction->symbol();
	    if (!defined( $holdings->{ $transaction->symbol() } )) {
		$holdings->{ $symbol } = Holding->new(
		    $transaction->ticker(),
		    $account);
	    }

	    # Finally append the transaction to the holding.
	    $transaction->setAccount($account_name);
	    $holdings->{$symbol}->appendTransaction($transaction);
	}
    }
    
    foreach my $symbol ( sort keys %{ $holdings } ) {
	$holdings->{$symbol}->computeAllFromTransactions();
    }
    return $account;
}

sub printToStringArray
{
    my($self, $raS, $prefix, $print_transactions) = @_;
    push @{$raS}, sprintf("%sAccount: \"%s\"",
			  $prefix,
			  $self->{_name});
    push @{$raS}, sprintf("%s  Taxable: \"%s\"",
			  $prefix,
			  defined($self->{_taxable})
			  ? sprintf("%d",$self->{_taxable})
			  : 'undef');
    my @holding_keys = sort keys %{ $self->{_holdings} };
    push @{$raS}, sprintf("%s  Number of Holdings: \"%d\"",
			  $prefix, scalar(@holding_keys));
    foreach my $symbol (@holding_keys) {
	$self->{_holdings}->{$symbol}->printToStringArray($raS,
	    $prefix . '  ', $print_transactions);
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

    $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ }) unless defined $csv;
    Util::printCsv($raTransCols, $csv, $raS);
    foreach my $symbol ( sort keys %{ $self->{_holdings} } ) {
	$self->{_holdings}->{$symbol}->printToCsvString(
	    $raTransCols, $rhNameMap, $csv, $raS);
    }
}
    
1;
