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

# Is the account tax advantaged?  e.g. and IRA or 401k.
my $gTaxAdvantaged = 'ta';

# Set of allowed ticker symbols.  The list need include only tickers
# that appear in the asset allocation for this account.
my $gAllowedTickers = 'at';

our $gAccountInfo = {
    'account1' => {
	$gTaxAdvantaged => 0,
    },
    'account2' => {
	$gTaxAdvantaged => 1,
    },
    'etrade' => {
	$gTaxAdvantaged => 0,
    },
    'etrade-5557' => {
	$gTaxAdvantaged => 0,
    },
    'etrade-ira' => {
	$gTaxAdvantaged => 1,
    },
    'etrade-joint', => {
	$gTaxAdvantaged => 0,
    },
    'schwab-annabelle', => {
	$gTaxAdvantaged => 0,
    },
    'schwab-bin', => {
	$gTaxAdvantaged => 1,
    },
    'schwab-bin-ira', => {
	$gTaxAdvantaged => 1,
    },
    'schwab-bin-401k', => {
	$gTaxAdvantaged => 1,
	$gAllowedTickers => [
	    'VBTSX',
	    'VWENX',
	    'VIPSX',
	    'VMISX',
	    'VSISX',
	    'PAAIX',
	    ],
    },
    'schwab-emil', => {
	$gTaxAdvantaged => 0,
    },
    'schwab-emil-401k', => {
	$gTaxAdvantaged => 1,
    },
    'schwab-emil-ira', => {
	$gTaxAdvantaged => 1,
    },
    'schwab-roth-ira', => {
	$gTaxAdvantaged => 1,
    },
    'schwab-shawhu', => {
	$gTaxAdvantaged => 0,
    },
    'van-brokerage', => {
	$gTaxAdvantaged => 0,
    },
    'van-goog-401k', => {
	$gTaxAdvantaged => 1,
    },
    'van-mut-funds', => {
	$gTaxAdvantaged => 0,
    },
    'van-rollover-ira', => {
	$gTaxAdvantaged => 1,
	$gAllowedTickers => [
	    'VAIPX',
	    'VBTSX',
	    'VUSUX',
	    'VBILX',
	    'VFIDX',
	    'VFIJX',
	    'VCVSX',
	    'VWEAX',
	    'VCAIX',
	    'VWENX',
	    'VWIAX',
	    'VIMAX',
	    'VEMAX',
	    'VFWAX',
	    'VFSVX',
	    ],
    },
    'van-roth-brokerage', => {
	$gTaxAdvantaged => 1,
    },
    'van-roth-mfs', => {
	$gTaxAdvantaged => 1,
    },
    'van-trad-ira-brok', => {
	$gTaxAdvantaged => 1,
    },
};

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
	_tax_advantaged => shift,
	_allowed_tickers => shift,
    };
    if (!defined($gAccountInfo->{$self->{_name}})) {
	die "No info for account $self->{_name}";
    }
    if (!defined($self->{_tax_advantaged})) {
	$self->{_tax_advantaged} = 
	    $gAccountInfo->{$self->{_name}}->{$gTaxAdvantaged};
    }
    if (!defined($self->{_allowed_tickers})) {
	$self->{_allowed_tickers} = 
	    $gAccountInfo->{$self->{_name}}->{$gAllowedTickers};
    }
    bless $self, $class;
    $gAccountsByName->{$self->{_name}} = $self;
    return $self;
}

sub name { $_[0]->{_name}; }
sub taxable { $_[0]->{_taxable}; }
sub holdings { $_[0]->{_holdings}; }
sub holding { $_[0]->{_holdings}->{$_[1]}; }
sub qif_filename { $_[0]->{_qif_filename}; }
sub tax_advantaged { $_[0]->{_tax_advantaged}; }
sub allowed_tickers { $_[0]->{_allowed_tickers}; }

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

    # Perform account level transformations, like replacing "transfer
    # in kind" operations.
    &optimize();
    
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
	$gDebug && print("  Creating new account $account_name\n");
	$holdings = {};
	$account = Account->new(
	    $account_name,
	    $taxable,
	    $holdings,
	    $qif_filename,
	    );
    }

    my $count = 0;
    while ( my $record = $qif->next ) {
	my $transaction = Transaction::newFromQifRecord($record, $account_name);
	if (defined($transaction)) {

	    # Create a new holding if needed.
	    my $symbol = $transaction->symbol();
	    if (!defined( $holdings->{ $transaction->symbol() } )) {
		$holdings->{ $symbol } = Holding->new(
		    $transaction->ticker(),
		    $account);
	    }

	    # Finally append the transaction to the holding.
	    $holdings->{$symbol}->appendTransaction($transaction);
	    $count++;
	}
    }
    $gDebug && printf("  Read %d transactions\n", $count); 
    foreach my $symbol ( keys %{ $holdings } ) {
	$holdings->{$symbol}->computeAllFromTransactions();
    }
    return $account;
}

sub optimize
{
    &handleTransferInKind();
}

# We actually move the transactions from the source account to the
# destination account, removing the transfer transactions.

# TODO: This is N-squared, but could probably be improved with
# memoization or the like.
sub handleTransferInKind
{
    # First look for each transfer-in and try to find a matching transfer out.
    my @transfers;
    foreach my $acct_name (keys %{$gAccountsByName}) {
	my $acct = $gAccountsByName->{$acct_name};
	foreach my $symbol (keys %{$acct->holdings()}) {
	    my $holding = $acct->holding($symbol);
	    if (! $holding->ticker()->skip()) {
		foreach my $transfer ( @{$holding->findTransfersIn()} ) {
# 		    my @strings;
# 		    $transfer->printToCsvString(\@strings);
# 		    print STDERR "Found Transfer In: ", join('',@strings);

		    push @transfers, $acct->handleTransferIn($holding, $transfer);
		}
	    }
	}
    }
    # After we've found all the transfers, do the moves.  Otherwise,
    # if there are more than one transfer of a holding (like
    # transfering lots), we won't be able to find the matching
    # transaction.
    foreach my $transfer (@transfers) {
	if (defined($transfer)) {
	    $transfer->{'acctIn'}->moveMatchingTransactions(
		$transfer->{'holding'},
		$transfer->{'transferIn'},
		$transfer->{'acctOut'},
		$transfer->{'transferOut'});
	}
    }
}

sub handleTransferIn
{
    my($self, $holding, $transferIn) = @_;

    my $transferOut;
    my $acctOut;
    foreach my $acct_name (keys %{$gAccountsByName}) {
	my $acct = $gAccountsByName->{$acct_name};
	next if ($self == $acct);
	# print STDERR "Looking for Matching Transfer Out in: ", $acct->name(), "\n";
	if (defined($acct->holdings()->{$holding->symbol()})) {
	    $transferOut = $acct->holding($holding->symbol())->
		findMatchingTransferOut($transferIn);
	    if (defined($transferOut)) {
		$acctOut = $acct;
		last;
	    }
	}
    }   
    if (!defined($transferOut)) {
	my @strings;
	$transferIn->printToCsvString(\@strings);
	print "No Matching Transfer Out For: ", join('',@strings);
	return undef;
    } else {
	return {
	    'acctIn' => $self,
	    'holding' => $holding,
	    'transferIn' => $transferIn,
	    'acctOut' => $acctOut,
	    'transferOut' => $transferOut};
    }
}

sub moveMatchingTransactions
{
    my ($self, $holding, $transferIn, $acctOut, $transferOut) = @_;

    # Should be able to move the entire holding.
    # Sanity Check:
    if (!defined($acctOut->holdings()->{$holding->symbol()})) {
# 	printf("WARNING: matching holding is gone. Must be more than one transfer for %s in %s\n",
# 	       $holding->symbol(), $self->name());
# 	my @strings;
# 	$transferOut->printToCsvString(\@strings);
# 	print "Transfer Out: ", join('',@strings);
# 	my @strings2;
# 	$transferIn->printToCsvString(\@strings2);
# 	print "Transfer In: ", join('',@strings2);
	return;
    }
    
    # Sanity Check:
    if ($acctOut->holding($holding->symbol())->shares() > 2.0) {
	printf("ERROR: There are still %f shares of %s in %s\n",
	       $holding->shares(), $holding->symbol(), $self->name());
	my @strings;
	$transferOut->printToCsvString(\@strings);
	print "Transfer Out: ", join('',@strings);
	my @strings2;
	$transferIn->printToCsvString(\@strings2);
	print "Transfer In: ", join('',@strings2);
	return;
    }

    # Move the transactions.
    $holding->prependHoldingTransactions($acctOut->holding($holding->symbol()));

    # Delete the holding from the account they moved from.
    delete $acctOut->holdings()->{$holding->symbol()};

    # Remove the transfers.
    # Not really necessary, and tricky to get right in the case where there
    # are more than one move for a given holding.
#    $holding->deleteTransaction($transferIn);
#    $holding->deleteTransaction($transferOut);
}

sub value
{
    my($self) = @_;
    my $value = 0;
    foreach my $h (keys %{$self->holdings()}) {
	if (! $self->holding($h)->ticker()->skip()) {
	    $value += $self->holding($h)->value();
	}
    }
    return $value;
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
       $raS,           # Out: Output is written back to this array. 
       $raFieldNames,  # In: Array of transaction column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $csv,           # In: A CSV object if you want to reuse one.
       $isMstar,       # In: Apply morningstar rules.
	) = @_;

    $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ }) unless defined $csv;
    Util::printCsv($raFieldNames, $csv, $raS);
    foreach my $symbol (sort keys %{ $self->{_holdings} }) {
	$self->{_holdings}->{$symbol}->printToCsvString(
	    $raS, $raFieldNames, $rhNameMap, $csv, $isMstar);
    }
}
    
1;
