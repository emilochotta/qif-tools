#!/bin/perl

# An account represents an investment account that can contain
# multiple assets.
package Account;

use Holding;
use Finance::QIF;
use Ticker qw($kCash);
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
my $gDisallowedTickers = 'da';

# While rebalancing can this account just grow and shrink as need be?
# e.g. a taxable brokerage account.  Or is the size fixed?
my $gFixedSize = 'fs';

# Symbol for cash held in this account.  If undefined, then this
# account can't hold cash.
my $gCashSymbol = 'cs';

# Priority of buying.  Low numbers are more likely to be bought in,
# all other factors being equal.
my $gPriority = 'pr';

our $gAccountInfo = {
    'account1' => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 0,
    },
    'account2' => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => undef,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 10,
    },
    'etrade' => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 100,
    },
    'etrade-5557' => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 100,
    },
    'etrade-ira' => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 100,
    },
    'etrade-joint', => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 100,
    },
    'schwab-annabelle', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 0,
    },
    'schwab-bin', => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 0,
    },
    'schwab-bin-ira', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 3,
    },
    'schwab-bin-401k', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => undef,
	$gAllowedTickers => [
	    'VBTSX',  # Total bond market
	    'VWENX',  # Wellington
	    'VIPSX',  # Inflation protected
	    'VMISX',  # Mid-cap signal
	    'VSISX',  # Small-cap signal
	    'PAAIX',  # World allocation
	    'PTTRX',  # Fixed income med term
	    'HAINX',  # Stock International
	    'POSKX',  # Stock US Large Cap
	    'NVLIX',  # Stock US Large Cap
	    'SWPPX',  # S&P 500
	    'TAVFX',  # Stock US Large Cap
	    'TILCX',  # Stock US Large Cap
	    ],
	$gPriority => 0,
    },
    'schwab-emil', => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 7,
    },
    'schwab-emil-401k', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => undef,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 100,
    },
    'schwab-emil-ira', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 100,
    },
    'schwab-roth-ira', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 100,
    },
    'schwab-shawhu', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gPriority => 0,
    },
    'van-brokerage', => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => 'VMMXX',
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 3,
    },
    'van-goog-401k', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => 'VMMXX',
	$gAllowedTickers => [  # Also support brokerage buys
	    'VBMPX',  # Vanguard Total Bond Mkt Ix Ist Pls
	    'VEMPX',  # Vanguard Ext Mkt Index Inst Plus
	    'VIIIX',  # Vanguard Inst Index Fund Inst Plus
	    'VTPSX',  # Vanguard Tot Intl Stock Ix Inst Pl
	    'VWIAX',  # Vanguard Wellesley Income Fund Adm
	    'VTHRX',  # Target Retirement 2030 Trust I
	    ],
	$gPriority => 1,
    },
    'van-mut-funds', => {
	$gTaxAdvantaged => 0,
	$gFixedSize => 0,
	$gCashSymbol => undef,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 6,
    },
    'van-rollover-ira', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => undef,
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
	$gPriority => 2,
    },
    'van-roth-brokerage', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => undef,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 4,
    },
    'van-roth-mfs', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 4,
    },
    'van-trad-ira-brok', => {
	$gTaxAdvantaged => 1,
	$gFixedSize => 1,
	$gCashSymbol => $Ticker::kCash,
	$gDisallowedTickers => [
	    'PAAIX',  # Institutional
	    'PTTRX',  # Institutional
	    'VEMPX',  # Institutional
	    'VIIIX',  # Institutional
	    'VMISX',  # Institutional
	    'VSISX',  # Institutional
	    ],
	$gPriority => 5,
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
	_fixed_size => shift,
	_cash_symbol => shift,
	_allowed_tickers => shift,
	_disallowed_tickers => shift,
	_priority => shift,
	_unallocated => shift,   # Cash amount temporarily unallocated
	                         # during rebalancing.
    };
    if (!defined($gAccountInfo->{$self->{_name}})) {
	die "No info for account $self->{_name}";
    }
    if (!defined($self->{_tax_advantaged})) {
	$self->{_tax_advantaged} = 
	    $gAccountInfo->{$self->{_name}}->{$gTaxAdvantaged};
    }
    if (!defined($self->{_fixed_size})) {
	$self->{_fixed_size} = 
	    $gAccountInfo->{$self->{_name}}->{$gFixedSize};
    }
    if (!defined($self->{_cash_symbol})) {
	$self->{_cash_symbol} = 
	    $gAccountInfo->{$self->{_name}}->{$gCashSymbol};
    }
    if (!defined($self->{_allowed_tickers})) {
	$self->{_allowed_tickers} = 
	    $gAccountInfo->{$self->{_name}}->{$gAllowedTickers};
    }
    if (!defined($self->{_disallowed_tickers})) {
	$self->{_disallowed_tickers} = 
	    $gAccountInfo->{$self->{_name}}->{$gDisallowedTickers};
    }
    if (!defined($self->{_priority})) {
	$self->{_priority} = 
	    $gAccountInfo->{$self->{_name}}->{$gPriority};
    }
    if (!defined($self->{_unallocated})) {
	$self->{_unallocated} = 0;
    }
    bless $self, $class;
    $gAccountsByName->{$self->{_name}} = $self;
    return $self;
}

sub newDeepCopy
{
    my ($self) = @_;
    my $copy_of_holdings = {};
    foreach my $symbol (keys %{ $self->{_holdings} }) {
	$copy_of_holdings->{$symbol} = $self->holding($symbol)->newDeepCopy();
    }
    my $copy = Account->new(
	$self->name(),
	$self->taxable(),
	$copy_of_holdings,
	$self->qif_filename(),
	$self->tax_advantaged(),   # This is const data
	$self->fixed_size(),       # This is const data
	$self->cash_symbol(),      # This is const data
	$self->allowed_tickers(),  # This is const data
	$self->disallowed_tickers(),  # This is const data
	$self->priority(),         # This is const data
	$self->unallocated(),
    );
    return $copy;
}

sub name { $_[0]->{_name}; }
sub taxable { $_[0]->{_taxable}; }
sub holdings { $_[0]->{_holdings}; }
sub holding { $_[0]->{_holdings}->{$_[1]}; }
sub qif_filename { $_[0]->{_qif_filename}; }
sub tax_advantaged { $_[0]->{_tax_advantaged}; }
sub fixed_size { $_[0]->{_fixed_size}; }
sub cash_symbol { $_[0]->{_cash_symbol}; }
sub allowed_tickers { $_[0]->{_allowed_tickers}; }
sub disallowed_tickers { $_[0]->{_disallowed_tickers}; }
sub priority { $_[0]->{_priority}; }
sub unallocated { $_[0]->{_unallocated}; }

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
 		    my @strings;
 		    $transfer->printToCsvString(\@strings);
 		    print "Found Transfer In: ", join('',@strings);

		    push @transfers, $acct->handleTransferIn($holding, $transfer);
		}
	    }
	}
    }
    
    #
    # Handle the case where a holding moves into an account and then
    # out again. For example, A1 -> A2 -> A3.  Look for these cases
    # and adjust the transfer to skip A2.  Loop until there are no
    # more such moves.
    #
    # TODO: does this work for A1->A2->A3->A4 ?
    my $num_multi_moves = 1;
    while ($num_multi_moves > 0) {
	$num_multi_moves = 0;
	foreach my $transfer1 (@transfers) {
	    foreach my $transfer2 (@transfers) {
		next if ($transfer1 == $transfer2);
		next unless (defined($transfer1));
		next unless (defined($transfer2));
		# Look for cases of A2 (see comment above).
		if ( ($transfer1->{'acctIn'} == $transfer2->{'acctOut'}) &&
		     ($transfer1->{'transferIn'}->ticker() == $transfer2->{'transferOut'}->ticker()) ) {

		    # Change A1 -> A2 to be A1->A3
		    # The holding is destination, so it needs to be changed.
		    $transfer1->{'holding'} = $transfer2->{'holding'};
		    $transfer1->{'acctIn'} = $transfer2->{'acctIn'};
		    # Shouldn't need to change the transaction
		    # $transfer1->{'transferIn'} = $transfer2->{'transferIn'};

		    $num_multi_moves++;
		    printf ("Changing move old(%s->%s) new(%s->%s) for %s\n",
			    $transfer1->{'acctOut'}, $transfer2->{'acctOut'},
			    $transfer1->{'acctOut'}, $transfer1->{'acctIn'},
			    $transfer1->{'holding'}->symbol());
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
        print "Looking for Matching Transfer Out in: ", $acct->name(), "\n";
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
	my @strings;
	$transferOut->printToCsvString(\@strings);
	print "... Matching Transfer Out: ", join('',@strings);

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

    print "moveMatchingTransactions\n";
    
    # Should be able to move the entire holding.
    # Sanity Check:
    if (!defined($acctOut->holdings()->{$holding->symbol()})) {
 	printf ("WARNING: matching holding is gone. Must be more than one transfer for %s in %s\n",
 	       $holding->symbol(), $self->name());
 	my @strings;
 	$transferOut->printToCsvString(\@strings);
 	print "Transfer Out: ", join('',@strings);
 	my @strings2;
 	$transferIn->printToCsvString(\@strings2);
 	print "Transfer In: ", join('',@strings2);
	return;
    }
    
    # Sanity Check:
    if ($acctOut->holding($holding->symbol())->shares() > 2.0) {
	printf ("ERROR: There are still %f shares of %s in %s\n",
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
    {
	my $transactions_to_move = $acctOut->holding($holding->symbol())->transactions();
	my @strings;
	$transactions_to_move->printToCsvString(\@strings);
	print "Transactions to move: ", join("...",@strings);
    }
    $holding->prependHoldingTransactions($acctOut->holding($holding->symbol()));

    # Delete the holding from the account they moved from.
    delete $acctOut->holdings()->{$holding->symbol()};

    # Remove the transfers.  Not really necessary, and tricky to get
    # right in the case where there are more than one move for a given
    # holding.  
    # $holding->deleteTransaction($transferIn);
    # $holding->deleteTransaction($transferOut);
}

# During rebalancing.  If this account has a fixed size (e.g. it is a
# 401K where the money can't easily be moved in/out), then the money
# has to be to/from our unallocated slush fund.  Return the amount of
# money that can be moved to the portfolio slush fund.
sub applyRebalanceTransaction {
    my($self, $transaction) = @_;
    my $action = $transaction->action();
    my $amount;
    if ($action eq 'Sell') {
	$amount = $transaction->amount();
    } elsif ($action eq 'Buy') {
	$amount = 0.0 - ($transaction->amount());
    } else {
	die "Can't handle transaction action $action";
    }
    my $amount_returned_to_portfolio = 0.0;
    if ($self->fixed_size()) {
	$self->{_unallocated} += $amount;
	if ( $self->{_unallocated} < -0.01 ) {
	    $transaction->print();
	    printf("Spent more money (%.2f) than we have in acct %s\n.",
		$amount, $self->name());
	}
    } else {
	$amount_returned_to_portfolio = $amount;
    }
	
    my $symbol = $transaction->symbol();

    if (!defined($self->holding($symbol))) {
	# New holding in this account.
	$self->holdings()->{$symbol} = Holding->new(
	    $transaction->ticker(),
	    $self);
    }
    $self->holding($symbol)->applyTransaction($transaction);
    return $amount_returned_to_portfolio;
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
    $value += $self->unallocated();
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
