#!/bin/perl

# A portfolio is a collection of holdings or accounts.

package Portfolio;

use Account;
use AssetAllocation;
use AssetCategory;
use Holding;
use RebalTran;
use Ticker qw($kCash);
use Transaction qw(&scalarFields);
use Transactions;
use Text::CSV_XS;
use Time::Format qw(%time time_format);
use Util;
use strict;

#-----------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------

my $gDebug = 1;

# Less than this number of shares is considered a zero balance
my $gZero = 2.0;

# Map from portfolio name to list of account names. 
our %PortfolioDefs = (
    'all' => [
	'etrade',
	'etrade-5557',
	'etrade-ira',
	'etrade-joint',
	'schwab-annabelle',
	'schwab-bin-ira',
	'schwab-bin-401k',
	'schwab-emil',
	'schwab-emil-401k',
	'schwab-emil-ira',
	'schwab-roth-ira',
	'schwab-shawhu',
	'van-brokerage',
	'van-goog-401k',
	'van-mut-funds',
	'van-rollover-ira',
	'van-roth-brokerage',
	'van-roth-mfs',
	'van-trad-ira-brok',
    ],	
    'me' => [
	'etrade',
	'etrade-5557',
	'etrade-ira',
	'etrade-joint',
	'schwab-bin-401k',
	'schwab-bin-ira',
	'schwab-emil',
	'schwab-emil-401k',
	'schwab-emil-ira',
	'schwab-roth-ira',
	'van-brokerage',
	'van-mut-funds',
	'van-rollover-ira',
	'van-roth-brokerage',
	'van-roth-mfs',
	'van-trad-ira-brok',
    ],	
    'amo' => [
	'schwab-annabelle',
    ],	
    'nso' => [
	'schwab-shawhu',
    ],	
    'bin' => [
	'schwab-bin-401k',
    ],	
    'goog' => [
	'van-goog-401k',
    ],	
    'etrade' => [
	'etrade',
    ],	
    );

# Use a bit vec for Analysis of holdings w.r.t. asset allocation.
our $IDEAL = 1;              # Practically perfect in every way.
our $OVER_ALLOCATION = 2;    # Too much of this holding.
our $HIGH_DIVIDEND_TAX = 4;  # High yield in a taxable account.
our $CAPITAL_LOSS = 8;       # Currently have a capital loss.
our $NON_IDEAL_TICKER = 16;  # Not the first ticker on the list.
our $CONSOLIDATE = 32;       # Spread across multiple accounts.

# _perCatData Portfolio analysis hash names / CSV column header names.
my $kCategory = 'Category';
my $kCatAllocTickers = 'Alloc Tickers';
my $kCatOwnedTickers = 'Owned Tickers';
my $kCatValue = 'Value';
my $kCatAllocation = 'Allocation';
my $kCatCurrentWeight = 'Current Weight';
my $kCatDifference = 'Difference';
my $kCatDiffPercent = 'Diff %';
my $kCatTargetValue = 'Target Value';
my $kCatTargetValueDiff = 'Target Value Diff';
my $kCatRebalance = 'Rebalance';
my $kCatTargetBuy = 'Target Buy';
my $kCatBuy = 'Buy';
my $kCatConsolidate = 'Multiple Accounts';

# _perHoldingData Portfolio analysis hash names / CSV column header names.
my $kHoldKey = 'Key';
my $kHoldName = 'Name';
my $kHoldTicker = 'Ticker';
my $kHoldAccount = 'Account';
my $kHoldCategory = 'Category';
my $kHoldPrice = 'Price';
my $kHoldShares = 'Shares';
my $kHoldValue = 'Value';
my $kHoldCostBasis = 'Cost Basis';
my $kHoldGain = 'Gain';
my $kHoldCashIn = 'CashIn';
my $kHoldReturnedCapital = 'Returned Capital';
my $kHoldReturn = 'Return';
my $kHoldROIC = 'ROIC';  # Return on Invested Capital
my $kHoldTaxAdvantaged = 'Tax Advantaged';
my $kHoldYield = 'Yield';
my $kHoldYieldVal = 'Est Yearly Yield';
my $kHoldIdealVal = 'Ideal Value';
my $kHoldBitVec = 'Analysis Bit Vec';
my $kHoldIdeal = 'Is Ideal';
my $kHoldOver = 'Over Allocation';
my $kHoldHighDiv = 'High Dividend Tax';
my $kHoldCapLoss = 'Capital Loss';
my $kHoldConsolidate = 'Multiple Accounts';

# _rebalInstructions hash names / CSV column header names.  These are
# only the first few columns.  The remainder of the columns names are
# holding keys (i.e. $kHoldKey).
my $kRebalKey = 'Key';
my $kRebalAction = 'Action';
my $kRebalReason = 'Reason';
my $kRebalShares = 'Shares';
my $kRebalAmount = 'Amount';
my $kRebalValue = 'Invested Value';
my $kRebalUnallocated = 'Unallocated';

#-----------------------------------------------------------------
# Global Variables with File Scope
#-----------------------------------------------------------------

my $PortfoliosByName = {};

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,             # Undefined for dups.

	# May be undefined.
	_assetAllocation => shift,

	# Hash by symbol.  Holdings and accounts.  Holdings aren't
	# shared by portfolios.
	_holdings => shift,

	# Hash by acct name.  Account objects can be shared across
	# multiple portfolios, so generally treated as read only.
	_accounts => shift,

	# Hash by assetAllocation category name.  Analysis of
	# portfolio against asset allocation.
	_perCatData => shift,

	# Hash by composite key "symbol/account".  Analysis of
	# portfolio against asset allocation.
	_perHoldingData => shift,

	# Array of transactions for rebalancing.
	_rebalTrans => shift,

	# Total portfolio value.  Calculated from holdings (not
	# accounts.)
	_value => shift,

	# Intermediate value used for rebalancing.  Cash value of sa
	# les.  Calculated from holdings (not
	# accounts.)
	_unallocated => shift,
    };
    if (defined($self->{_name}) &&
	defined($PortfoliosByName->{$self->{_name}})) {
	die "A portfolio named $self->{_name} already exists.\n";
    }
    if (!defined($self->{_perCatData})) {
	$self->{_perCatData} = {};
    }
    if (!defined($self->{_perHoldingData})) {
	$self->{_perHoldingData} = {};
    }
    if (!defined($self->{_rebalTrans})) {
	$self->{_rebalTrans} = [];
    }
    
    bless $self, $class;
    if (defined($self->{_name})) {
	$PortfoliosByName->{$self->{_name}} = $self;
    }
    return $self;
}

# Not really a complete deep copy.  Used for duplicates that show the
# progression of a portfolio as it is rebalanced.
sub newDeepCopy
{
    my ($self) = @_;
    my $copy_of_holdings = {};
    foreach my $symbol (keys %{ $self->{_holdings} }) {
	$copy_of_holdings->{$symbol} = $self->holding($symbol)->newDeepCopy();
    }
    my $copy_of_accounts = {};
    foreach my $acct_name (keys %{ $self->{_accounts} }) {
	$copy_of_accounts->{$acct_name} = $self->account($acct_name)->newDeepCopy();
    }
    return Portfolio->new(
	undef,                    # Because portfolios are stored in global hash
	$self->assetAllocation(),
	$copy_of_holdings,
	$copy_of_accounts,
	$self->perCatData(),      # Shallow copy
	$self->perHoldingData(),  # Shallow copy
	$self->rebalTrans(),      # Shallow copy
	$self->value(),
	$self->unallocated(),
    );
}

sub name { $_[0]->{_name}; }
sub assetAllocation { $_[0]->{_assetAllocation}; }
sub holdings { $_[0]->{_holdings}; }
sub holding { $_[0]->{_holdings}->{$_[1]}; }
sub accounts { $_[0]->{_accounts}; }
sub account { $_[0]->{_accounts}->{$_[1]}; }
sub perCatData { $_[0]->{_perCatData}; }
sub perHoldingData { $_[0]->{_perHoldingData}; }
sub rebalTrans { $_[0]->{_rebalTrans}; }
sub value { $_[0]->{_value}; }
sub unallocated { $_[0]->{_unallocated}; }

sub SetAssetAllocation { $_[0]->{_assetAllocation} = $_[1]; }

sub newOrGetByName
{
    my ($name) = @_;

    # Share the objects instead of allocating new ones.
    if ( defined($name) && defined($PortfoliosByName->{$name})) {
	return $PortfoliosByName->{$name};
    }
    return Portfolio->new($name);
}

# How to use this:
# Create a portfolio value report in quicken using these steps:
#  Select Reports -> Investing -> Portfolio Value
#  Resolve any placeholder entries (see link at bottom of report).
#  Select Export Data to excel compatible format
#  Save as quicken-portfolio.txt (or whatever filename)
#  Open in excel
#  Save as quicken-portfolio.csv
sub newFromQuickenSummaryReport
{
    my($name, $csv_file) = @_;

    my $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ });
    open my $io, "<", $csv_file or die "$csv_file: $!";

    # Skip to data
    while (my $row = $csv->getline ($io)) {
	last if ( $row->[1] eq 'Security' );
    }
    # Skip extra blank row
    $csv->getline ($io);

    # Create the portfolio object
    my $portfolio = Portfolio->new($name, undef, undef, undef);
    
    # handle the transactions
    while (my $row = $csv->getline ($io)) {
	my $name = $row->[1];
	my $shares = $row->[2];
	$shares =~ tr/,\r//d;
	next if $shares eq "";
	my $price = $row->[3];
	$price =~ tr/,\r//d;
	my $estimated = ($row->[4] ne '');
	my $cost_basis = $row->[5];
	$cost_basis =~ tr/,\r//d;
	my $gain = $row->[6];
	$gain =~ tr/,\r//d;
	my $value = $row->[7];
	$value =~ tr/,\r//d;
	my $ticker = Ticker::getByName($name);

	if ( ! $ticker->skip() ) {

	    my $holding = Holding->new(
		$ticker,
		undef,  # No account
		undef,  # No assetCategory
		undef,  # No transactions
		$shares,
		$price,
		$estimated,
		$cost_basis,
		$gain,
		$value,
		undef,  # purchases
		undef,  # investment return
		);

	    $portfolio->{_holdings}->{$ticker->symbol()} = $holding;
	    
# 	    $gDebug && printf("Found %f shares of \"%s\" at %.2f\n",
# 			      $holding->shares(), $name,
# 			      $holding->price());
	}
    }
    close $io;
    return $portfolio;
}
    
sub Set_Asset_Allocation {
    my ($self, $a) = @_;
    $self->{_assetAllocation} = $a if defined $a;

    # Assign the AssetCategory to holdings of the portfolio, but not
    # of the accounts because account objects are shared by multiple
    # portfolios but AssetAllocation is per portfolio.
    foreach my $symbol (keys %{$self->holdings()}) {

	# Need also check if this is defined.
	if (defined($a->symbol($symbol))) {
	    $self->holding($symbol)->setAssetCategory($a->symbol($symbol));
	} else {
	    die "No asset category for $symbol in portfolio $self->name()";
	}
    }    
    return $self->{_assetAllocation};
}

sub Add_Account {
    my ($self, $account) = @_;
    die "Account undefined" unless (defined $account);
    push @{ $self->{_accounts} }, $account;
    return $self->{_accounts};
}

sub newPortfoliosFromAccounts {	
    my ($rhAccts, $rhPortfolioDefs) = @_;

    foreach my $portfolio_name (keys %{ $rhPortfolioDefs }) {
	my $p = Portfolio->new($portfolio_name);
	foreach my $account_name (@{ $rhPortfolioDefs->{$portfolio_name} }) {
	    if (!defined($rhAccts->{$account_name})) {
		die "Account $account_name needed for Portfolio ",
		$portfolio_name, " doesn't exist.\n";
	    }
	    my $account = $rhAccts->{$account_name};
	    $p->{_accounts}->{$account_name} = $account;

	    # Add the holdings from this account to the holdings for
	    # this portfolio.
	    foreach my $symbol (keys %{ $account->holdings() }) {
		my $deb = 0;
#		$deb = 1 if ($symbol eq 'DJP');
		next if ($account->holding($symbol)->ticker()->skip());
		if ($deb) {
		    printf("Add Account %s Holding of %s to Portfolio %s\n",
			   $account_name, $symbol, $portfolio_name);
		    $account->holding($symbol)->print();
		    }
		if (defined($p->{_holdings}) &&
		    defined($p->{_holdings}->{$symbol})) {

		    # Holding with this symbol already exists, so
		    # we append the transactions from this account
		    # to the transactions for that other account.
		    my $holding = $p->holding($symbol);
		    if ($deb) {
			print "** Merge With **\n";
			printf("Portfolio %s Holding of %s\n",
			       $portfolio_name, $symbol);
			$holding->print();
		    }
		    $holding->appendHoldingTransactions(
			$account->holding($symbol));
		} else {
		    if ($deb) {
			print "** Copy **\n";
		    }
		    $p->{_holdings}->{$symbol} =
			$account->holding($symbol)->newDeepCopy();
		}
		if ($deb) {
		    printf("After Adding Portfolio %s Holding of %s:\n",
			   $portfolio_name, $symbol);
		    $p->holding($symbol)->print();
		}
	    }
	}
    }
    return $PortfoliosByName;
}

sub Compare {
    my ($self, $other, $raS) = @_;
    
    my @my_symbols;
    my $width = 6;
    foreach my $symbol (sort keys %{$self->holdings()}) {
	if (!$self->holding($symbol)->ticker()->skip()) {
	    push @my_symbols, $symbol;
	    if (length $symbol > $width) {
		$width = length $symbol;
	    }
	}
    }

    my @big_diffs;
    push @{$raS}, sprintf(
	"| %${width}s |  %10s | %10s |    %10s    |",
	'SYMBOL', $self->name(), $other->name(), 'DIFFERENCE');
    foreach my $symbol (@my_symbols) {
	my $line = sprintf("| %${width}s | ", $symbol);
	if (! defined $other->holdings()->{$symbol}) {
	    $line .= sprintf(
		"WARNING: No holding in Portfolio \"%s\" for %f shares in Portfolio\"%s\"",
		$other->name(), $self->holding($symbol)->shares(), name());
	} else {
	    my $my_shares = $self->holding($symbol)->shares();
	    my $other_shares = $other->holding($symbol)->shares();
	    my $difference = $my_shares - $other_shares;
	    my $stars = '  ';
	    if ( abs($difference) > $gZero ) {
		$stars = '**';
		push @big_diffs, $other->holding($symbol);
	    }
	    $line .= sprintf(
		" %10.3f | %10.3f | %s %10.3f %s |",
		$my_shares, $other_shares, $stars, $difference, $stars);
	}
	push @{$raS}, $line;
    }
    foreach my $holding (@big_diffs) {
	$holding->printToCsvFile($holding->symbol() . '.csv');
    }
}

sub copyPrices
{
    my($self,
       $other) = @_;
    
    foreach my $h (keys %{$self->holdings()}) {
	my $ticker = $self->holding($h)->ticker();
	if (! $ticker->skip()) {
	    if (defined($other->holding($h))) {
		$self->holding($h)->copyPrice($other->holding($h));
	    } elsif ($h eq $Ticker::kCash) {
		$self->holding($h)->setPrice(1.0);
	    } elsif (defined($ticker->attribute('Price'))
		     && $ticker->attribute('Price') != 0) {
		$self->holding($h)->setPrice($ticker->attribute('Price'));
	    } else {
		printf("WARNING: No price for holding \"%s\"\n", $h);
	    }
	}
    }
    foreach my $a (keys %{$self->accounts()}) {
	my $account = $self->accounts()->{$a};
	foreach my $h (keys %{$account->holdings()}) {
#	    printf("Copy prices for %s in acct %s\n", $h, $a);
	    my $ticker = $account->holding($h)->ticker();
	    if (! $ticker->skip()) {
		if (defined($other->holding($h))) {
		    $account->holding($h)->copyPrice($other->holding($h));
		} elsif ($h eq $Ticker::kCash) {
		    $account->holding($h)->setPrice(1.0);
		} elsif (defined($ticker->attribute('Price'))
			 && $ticker->attribute('Price') != 0) {
		    $self->holding($h)->setPrice(
			$ticker->attribute('Price'));
		} else {
		    printf("WARNING: No price for holding \"%s\"\n", $h);
		}
	    }
	}
    }
}

sub printToCsvString
{
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $raFieldNames,  # In: Array of column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $csv,           # In: A CSV object if you want to reuse one.
       $isMstar,       # In: Apply morningstar rules.
	) = @_;

    
    if (!defined $raFieldNames) {
	my $t = Transaction->new();
	$raFieldNames = $t->scalarFields();
    }
    $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ }) unless defined $csv;
    Util::printCsv($raFieldNames, $csv, $raS);
    foreach my $symbol (sort keys %{ $self->{_holdings} }) {
 	$self->holding($symbol)->printToCsvString(
 	    $raS, $raFieldNames, $rhNameMap, $csv, $isMstar);
    }
}
    
sub printToCsvFile
{
    my($self,
       $fname,
       $raFieldNames,  # In: Array of transaction column names to print.
                       #   If undef, then it will use all scalar fields.
       $rhNameMap,     # In: Indirect the FieldName through this map.
                       #   If undef, use the FieldNames directly.
       $isMstar,       # In: Apply morningstar rules.
       ) = @_;
    my @S;
    open my $io, ">", $fname or die "$fname: $!";
    print STDERR "  Writing $fname\n";
    $isMstar = 0 unless defined $isMstar;
    $self->printToCsvString(\@S, $raFieldNames, $rhNameMap, undef, $isMstar);
    print $io @S;
    close $io;
}

# Uses the Morningstar headers
sub printToMstarCsvFile
{
    my($self,
       $fname,
       ) = @_;
    $self->printToCsvFile($fname, \@Transaction::MstarHeaders,
			  \%Transaction::MstarMap, 1);
}


sub printRebalanceCsvString
{
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $csv,           # In: A CSV object if you want to reuse one.
	) = @_;

    $csv = Text::CSV_XS->new unless defined $csv;

    # Need all these fields defined.
    return unless
	defined($self->assetAllocation())
	&& defined($self->holdings())
	&& defined($self->accounts());
    
    $self->analyzeHoldingsAgainstAllocations();
    $self->printCategoryLinesString(
	$raS,
	$csv);
    $self->printTickerLinesString(
	$raS,
	$csv);

    # Need to produce a set of transactions that are the proposed
    # trades to balance the portfolio.
    #
    # First, find assets that are high yield but not in tax advantaged
    # accounts.
    #
    # Algorithm:
    # 1) Find total available value in tax advantaged accounts.
    #
    # 2) [Skip this.] Compute portfolio of ideal holdings according to asset
    #    allocation.
    #
    # 3) Iterate through ideal holdings ordered by estimated yearly
    #    dividend, subtracting holding values until out of room.
    #   - Discard any holdings already in a tax advantaged account.
    #   - Discard any holdings with capital loss, since those
    #     have weird tax laws.
    # 
    # 4) Sell any holdings in the tax advantaged accounts not
    #    identified as part of the list from 3.
    #   - Certain accounts have limited symbols they can hold, e.g.
    #     Vanguard IRA can hold only mutual funds.  So, we need to
    #     obey these rules.
    #
    # 5) Sell non-ideal assets? Assets over allocation?
    #    Asset categories split into multiple accounts?
    #
    # 6) Use a simple greedy algorithm to buy the assets back into
    #    accounts.
    #
    # Stuff we need:
    #  - target portfolio.  Calculated from asset allocation.
    #  - rebalancing transactions.
    #  - How to print out the transactions?
    #  - Cash management.
    #  - Account info: tax advantaged, allowable tickers in account.
    #  - Ticker info: yield.

    #
    # Create hash per rebalance move:
    #  - Transaction
    #  - Unallocated cash
    #  - Resulting portfolio

    # Need to handle tickers that are high yield but not taxable,
    # i.e. muni funds.  Are gov bonds taxable?  Need to check my actual taxes.
    
    $self->sellHighYieldInTaxableAccount();

    $self->printRebalanceLinesString(
	$raS,
 	$csv);
}
    
# The basic analysis was already done (in AnalyzeHoldings). 
sub sellHighYieldInTaxableAccount {
    my($self) = @_;

    # Sell high yield holdings from taxable accounts
    foreach my $key (sort
		     { $self->{_perHoldingData}->{$a}->{$kHoldYieldVal}
		       <=> $self->{_perHoldingData}->{$b}->{$kHoldYieldVal} }
		     keys %{ $self->{_perHoldingData} }) {
	my $hold_data = $self->{_perHoldingData}->{$key};

	next unless ($hold_data->{$kHoldHighDiv});

	# Never move a holding from taxable to non taxable if there is
	# a capital loss.  This was also checked in AnalyzeHoldings.
	if ($hold_data->{$kHoldGain} >= 0) {
	    $self->rebalanceSale($hold_data,
				 'High Yield In Taxable Account');
	}
    }

    # Now Sell non high yield holdings from non taxable accounts to
    # make room for them.
    foreach my $acct_name (keys %{ $self->accounts() }) {
	my $acct = $self->accounts()->{$acct_name};
	next unless $acct->tax_advantaged();
	foreach my $symbol (keys %{ $acct->holdings() }) {
	    my $key = &holdingKey($symbol, $acct_name);
	    my $holding = $acct->holdings()->{$symbol};
	    my $ticker = $holding->ticker();
	    next if ($ticker->skip());
	    my $shares = $holding->shares();
	    next if ($shares < $gZero);
	    printf("Selling For Rebalance: %s\n", $symbol);
	    my $hold_data = $self->{_perHoldingData}->{$key};

	    # Only sell holdings that aren't high dividend.
	    next if ($hold_data->{$kHoldHighDiv});

	    # Okay, get rid of it.
	    $self->rebalanceSale($hold_data, 
				 'Low Yield In Tax Advantaged');
	}
    }
}

# Utility for all rebalance sale transactions.
sub rebalanceSale {
    my($self, $hold_data, $reason) = @_;

    # The rebalance transaction is relative to the last rebalance
    # transaction/portfolio already stored in self.  So, need to find
    # that last one and make a deep copy of it.
    my $starting_portfolio = $self;
    my $num_rebalance_steps = scalar(@{$self->{_rebalTrans}});
    if ($num_rebalance_steps > 0) {
	$starting_portfolio =
	    $self->{_rebalTrans}->[$num_rebalance_steps-1]->portfolio();
    }
    my $deep_copy = $starting_portfolio->newDeepCopy();
    my $rebal_trans = RebalTran::newSale(
	$reason,
	$hold_data->{$kHoldName},
	Ticker::getBySymbol($hold_data->{$kHoldTicker}),
	$hold_data->{$kHoldTicker},
	$hold_data->{$kHoldAccount},
	$hold_data->{$kHoldPrice},
	$hold_data->{$kHoldShares},
	$deep_copy);
    $deep_copy->applyTransaction($rebal_trans->transaction());
    push @{$self->{_rebalTrans}}, $rebal_trans;
}

sub calculateValue {
    my($self) = @_;

    $self->{_value} = 0;
    foreach my $symbol (keys %{$self->holdings()}) {
	my $holding = $self->holding($symbol);
	my $ticker = $holding->ticker();
	if (!$ticker->skip()) {
	    $self->{_value} += $holding->value();
	}
    }
    die "Total Portfolio Value is zero" if ($self->{_value} == 0.0);
}

sub holdingKey {
    my($symbol, $acct_name) = @_;
    return "$symbol/$acct_name";
}

sub applyTransaction {
    my($self, $transaction) = @_;
    my $action = $transaction->action();
    if ($action eq 'Sell') {
	$self->{_unallocated} += $transaction->amount();
    } elsif ($action eq 'Buy') {
	$self->{_unallocated} -= $transaction->amount();
	if ( $self->{_unallocated} < 0 ) {
	    die "Spent more money that we have.";
	}
    } else {
	die "Can't handle transaction action $action";
    }
	
    my $symbol = $transaction->symbol();
    if (defined($self->holding($symbol))) {
	$self->holding($symbol)->applyTransaction($transaction);
    }
    my $acct_name = $transaction->account();
    if (defined($self->account($acct_name))) {
	my $acct = $self->account($acct_name);
	$acct->applyRebalanceTransaction($transaction);
    }
    $self->calculateValue();
}

sub analyzeHoldingsAgainstAllocations {
    my($self) = @_;
    if (!defined($self->{_value})) {
	$self->calculateValue();
    }

    my $total_portfolio_value = 0;
    my $total_alloc = 0;  # Just a sanity check
    my $excess_buy = 0;  # This is the sum of all the buys & sells proposed for rebalancing
    my $alloc = $self->{_assetAllocation};
    foreach my $cat_name (sort keys %{ $alloc->categories() }) {
	my $category_value = 0;
	my $category = $alloc->category($cat_name);
	my $raTickerSymbols = $category->symbols();
	my $alloc_value = $category->value() / 100.0;
	$total_alloc += $alloc_value;

	my @owned_symbols;
	my @alloc_symbols;
	foreach my $symbol (sort @{ $raTickerSymbols }) {
	    push @alloc_symbols, $symbol;
	    if (defined($self->holding($symbol))) {
		$category_value += $self->holding($symbol)->value();
		push @owned_symbols, $symbol;
	    }
	}
	$total_portfolio_value += $category_value;
# 	$gDebug && printf("Category %s = %f, total %f\n",
# 			  $cat_name, $category_value,
# 			  $total_portfolio_value);
	my $alloc_symbols = join(",", @alloc_symbols);
	my $owned_symbols = join(",", @owned_symbols);

	next if $alloc_value == 0 && $category_value == 0;

	$self->{_perCatData}->{$cat_name} = {};
	my $cat_data = $self->{_perCatData}->{$cat_name};
	$cat_data->{$kCategory} = $cat_name;
	$cat_data->{$kCatAllocTickers} = $alloc_symbols;
	$cat_data->{$kCatOwnedTickers} = $owned_symbols;
	$cat_data->{$kCatConsolidate} = (scalar(@owned_symbols)>1);
	$cat_data->{$kCatValue} = $category_value;
	$cat_data->{$kCatAllocation} = $alloc_value;

	my $current_weight = $category_value / $self->value();
	$cat_data->{$kCatCurrentWeight} = $current_weight;
	
	my $difference =
	    $cat_data->{$kCatAllocation} - $current_weight;
	$cat_data->{$kCatDifference} = $difference;

	my $diff_percent = 0;
	if ( $cat_data->{$kCatAllocation} != 0 ) {
	    $diff_percent =
		$difference / $cat_data->{$kCatAllocation};
	}
	$cat_data->{$kCatDiffPercent} = $diff_percent;

	my $target_value = $self->value() * $cat_data->{$kCatAllocation};
	$cat_data->{$kCatTargetValue} = $target_value;

	my $target_value_diff = $target_value - $category_value;
	$cat_data->{$kCatTargetValueDiff} = $target_value_diff;

	my $rebalance = 0;
	my $target_buy = 0;

	# Rebalance rule: more than 5% delta and > $5000 difference.
	if ( (abs($diff_percent) > 0.05 || abs($diff_percent) == 0.0)
	     && abs($target_value_diff) > 5000 ) {
	    $rebalance = 1;
	    $target_buy = $target_value_diff;
	    $excess_buy += $target_buy;
	}	    
	$cat_data->{$kCatRebalance} = $rebalance;
	$cat_data->{$kCatTargetBuy} = $target_buy;
    }

    if ( $total_alloc ne 1.0 ) {
	printf("Warning: Total Asset Allocation isn't 1, it's %f, (diff %f)\n",
	    $total_alloc, 1.0 - $total_alloc);
    }
    if (abs($total_portfolio_value-$self->value()) > $gZero) {
	printf("Warning: Total Portfolio Value by asset claass (%f) != value by holding (%f)\n",
	    $total_portfolio_value, $self->value());
    }

    # Now go through by holding/account.
    my $totalTaxAdvantagedValue = 0;
    foreach my $acct_name (keys %{ $self->accounts() }) {
	my $acct = $self->accounts()->{$acct_name};
	foreach my $symbol (keys %{ $acct->holdings() }) {
	    my $key = &holdingKey($symbol, $acct_name);
	    my $holding = $acct->holdings()->{$symbol};
	    my $ticker = $holding->ticker();
	    next if ($ticker->skip());
	    my $shares = $holding->shares();
	    next if ($shares < $gZero);
	    
	    $self->{_perHoldingData}->{$key} = {};
	    my $hold_data = $self->{_perHoldingData}->{$key};
	    
	    $hold_data->{$kHoldKey} = $key;
	    $hold_data->{$kHoldAccount} = $acct_name;
	    $hold_data->{$kHoldName} = $ticker->name();
	    $hold_data->{$kHoldTicker} = $symbol;
	    $hold_data->{$kHoldPrice} = $holding->price();
	    $hold_data->{$kHoldShares} = $shares;
	    my $value = $holding->value();
	    $hold_data->{$kHoldValue} = $value;
	    $hold_data->{$kHoldCostBasis} = $holding->cost_basis();
	    $hold_data->{$kHoldGain} = $holding->gain();
	    $hold_data->{$kHoldCashIn} = $holding->cashIn();
	    $hold_data->{$kHoldReturnedCapital} = $holding->returnedCapital();
	    $hold_data->{$kHoldReturn} = $holding->myReturn();
	    if ($holding->cashIn() > 0) {
		$hold_data->{$kHoldROIC} =
		    100.0 * $holding->myReturn() / $holding->cashIn();
	    } else {
		$hold_data->{$kHoldROIC} = 0;
	    }
	    $hold_data->{$kHoldTaxAdvantaged} =
		($acct->tax_advantaged()) ? $value : 0;
	    $totalTaxAdvantagedValue += $hold_data->{$kHoldTaxAdvantaged};
	    $hold_data->{$kHoldYield} = $ticker->attribute('Yield');
	    
	    my $vec = 0;
	    if (defined $self->assetAllocation()->symbols()->{$symbol}) {
		my $cat_name = $hold_data->{$kHoldCategory} = 
		    $self->assetAllocation()->symbols()->{$symbol}->name();
		my $cat_data = $self->{_perCatData}->{$cat_name};
		
		# Set ideal value to 0 unless this is the first symbol
		# in this asset category.  If it is the ideal symbol,
		# then set the value to the new rebalanced value if it
		# needs to be rebalanced.  Otherwise, keep it's value
		# as ideal.
		my $asset_category = 
		    $self->assetAllocation()->category($cat_name);
		my $ideal_symbol = $asset_category->symbols()->[0];
		if ( $symbol ne $ideal_symbol ) {
		    $hold_data->{$kHoldIdealVal} = 0;
		} elsif ( $cat_data->{$kCatRebalance} ) {
		    $hold_data->{$kHoldIdealVal} = 
			$cat_data->{$kCatTargetValue};
		} else {
		    $hold_data->{$kHoldIdealVal} = $value;
		}

		$hold_data->{$kHoldYieldVal} =
		    $hold_data->{$kHoldIdealVal} * 
		    $ticker->attribute('Yield') / 100.0;

		if ($cat_data->{$kCatTargetBuy} < 0) {
		    $vec |= $OVER_ALLOCATION;
		    $hold_data->{$kHoldOver} = 1;
		}
		if ($cat_data->{$kCatConsolidate}) {
		    $vec |= $CONSOLIDATE;
		    $hold_data->{$kHoldConsolidate} = 1;
		}
		if ($hold_data->{$kHoldGain} < 0.0) {
		    $vec |= $CAPITAL_LOSS;
		    $hold_data->{$kHoldCapLoss} = 1;
		}
	    } else {
		$hold_data->{$kHoldCategory} = 'unknown';
		print "WARNING: No asset allocation class for ticker \"$symbol\"\n";
		printf("Add that ticker to asset-allocation-%s.csv\n",
		       $self->name());
	    }
	    $hold_data->{$kHoldBitVec} = $vec;
	}
    }

#    printf("Tax Advantaged total is %f\n", $totalTaxAdvantagedValue);

    # Go through holdings by order of yield value and determine which
    # holdings should be in tax advantaged accounts based on the ideal
    # value of that holding.
    my $availableTaxAdvantagedValue = $totalTaxAdvantagedValue;
    foreach my $key (sort
		     { $self->{_perHoldingData}->{$b}->{$kHoldYieldVal}
		       <=> $self->{_perHoldingData}->{$a}->{$kHoldYieldVal} }
		     keys %{ $self->{_perHoldingData} }) {
	last if ($availableTaxAdvantagedValue < $gZero);
	my $hold_data = $self->{_perHoldingData}->{$key};

	# Don't mess with holdings that currently have capital loss,
	# since tax treatment is unfavorable.  In this case, don't
	# adjust availableValue either, since we won't put in a tax
	# advantaged account.
	if ($hold_data->{$kHoldGain} >= 0) {
	    # Not tax advantaged but there is available space in tax
	    # advantaged accounts to make it so.
	    if ($hold_data->{$kHoldTaxAdvantaged} == 0) {
		$hold_data->{$kHoldBitVec} |= $HIGH_DIVIDEND_TAX;
		$hold_data->{$kHoldHighDiv} = 1;
	    }

	    # Reduce available room whether it's already tax
	    # advantaged or not.  Use the ideal value, since 
	    # we'll want to buy the amount post-rebalancing.
	    $availableTaxAdvantagedValue -= $hold_data->{$kHoldIdealVal};
	}
    }
}

sub printCategoryLinesString {
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $csv,           # In: A CSV object if you want to reuse one.
	) = @_;

    my $column_headers = [$kCategory, $kCatAllocTickers,
			  $kCatOwnedTickers, $kCatValue,
			  $kCatAllocation, $kCatCurrentWeight,
			  $kCatDifference, $kCatDiffPercent,
			  $kCatTargetValue, $kCatTargetValueDiff,
			  $kCatRebalance, $kCatTargetBuy, $kCatBuy];
			  &Util::printCsv($column_headers, $csv,
			  $raS);

    # Now write it out
    foreach my $cat_name (sort
			  { $self->{_perCatData}->{$b}->{$kCatTargetValueDiff}
			    <=> $self->{_perCatData}->{$a}->{$kCatTargetValueDiff} }
			  keys %{ $self->{_perCatData} }) {
# 	foreach my $k (@{$column_headers}) {
# 	    printf("%s = %s,", $k, $self->{_perCatData}->{$cat_name}->{$k});
# 	}
# 	print "\n";
	&Util::printHashToCsv($self->{_perCatData}->{$cat_name},
			      $column_headers,
			      undef, $csv, $raS);
    }
    my $totals = {};
    $totals->{$kCatValue} = $self->value();
    # $totals->{$kBuy} = $excess_buy;
    &Util::printHashToCsv($totals, $column_headers,
			  undef, $csv, $raS);
}

sub printTickerLinesString {
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $csv,           # In: A CSV object if you want to reuse one.
	) = @_;

    my $column_headers = [ $kHoldName, $kHoldKey, $kHoldTicker,
			   $kHoldAccount, $kHoldCategory, $kHoldPrice,
			   $kHoldShares, $kHoldValue, $kHoldCostBasis,
			   $kHoldGain, $kHoldCashIn,
			   $kHoldReturnedCapital, $kHoldReturn,
			   $kHoldROIC, $kHoldTaxAdvantaged,
			   $kHoldYield, $kHoldIdealVal,
			   $kHoldYieldVal, $kHoldBitVec, $kHoldIdeal,
			   $kHoldOver, $kHoldHighDiv, $kHoldCapLoss,
			   $kHoldConsolidate, ];

    push @{$raS}, "\n";
    &Util::printCsv($column_headers, $csv, $raS);

    # Now write it out
    foreach my $key (sort
		     { $self->{_perHoldingData}->{$b}->{$kHoldYieldVal}
		       <=> $self->{_perHoldingData}->{$a}->{$kHoldYieldVal} }
		     keys %{ $self->{_perHoldingData} }) {
	&Util::printHashToCsv($self->{_perHoldingData}->{$key},
			      $column_headers,
			      undef, $csv, $raS);
    }
}

sub printRebalanceLinesString {
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $csv,           # In: A CSV object if you want to reuse one.
	) = @_;

    push @{$raS}, "\n";
    my $column_headers = $self->oneLinePortfolioColumnHeaders();
    &Util::printCsv($column_headers, $csv, $raS);

    $self->printOneLinePortfolioString(
	$raS,
	'Starting Portfolio',
	undef,
	$column_headers,
	$csv,
	);
    foreach my $rebalTran (@{$self->{_rebalTrans}}) {
	$rebalTran->portfolio()->printOneLinePortfolioString(
	    $raS,
	    $rebalTran->reason(),
	    $rebalTran->transaction(),
	    $column_headers,
	    $csv,
	    );
    }
}

# Returns the column headers needed for printOneLinePortfolioString
sub oneLinePortfolioColumnHeaders {
    my($self, $final_portfolio) = @_;
    my $column_headers = [
	$kRebalReason,
	$kRebalKey,
	$kRebalAction,
	$kRebalShares,
	$kRebalAmount,
	$kRebalValue,
	$kRebalUnallocated,
	];

    foreach my $acct_name (sort keys %{$self->accounts()}) {
	my $acct = $self->accounts()->{$acct_name};

	# For accounts that don't easily support moving money in/out,
	# keep track of the unallocated money separately as well as in
	# $kRebalUnallocated.
	if ( $acct->value() > $gZero && $acct->fixed_size() ) {
	    my $key = sprintf("unalloc %s", $acct->name());
	    push @{$column_headers}, $key;
	}
	foreach my $symbol (sort keys %{ $acct->holdings() }) {
	    my $key = "$symbol/$acct_name";
	    my $holding = $acct->holdings()->{$symbol};
	    if ($holding->value() > $gZero) {
		push @{$column_headers}, $key;
	    }
	}
    }
    return $column_headers;
}

sub printOneLinePortfolioString {
    my($self,
       $raS,            # Out: Output is written back to this array. 
       $reason,         # In: Reason string
       $transaction,    # In: Undef, or transaction that created this portfolio
       $column_headers, # In: If undef, calls oneLinePortfolioColumnHeaders.
       $csv,            # In: A CSV object if you want to reuse one.
	) = @_;

    $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ }) unless defined $csv;
    $column_headers = $self->oneLinePortfolioColumnHeaders()
	unless defined $column_headers;
    my $row = {};
    if (defined $transaction) {
	if (ref($transaction) ne 'Transaction') {
	    print "ERROR: transaction argument must be a Transaction.";
	}
	$row->{$kRebalKey} = &holdingKey($transaction->symbol(),
					 $transaction->account());
	$row->{$kRebalAction} = $transaction->action();
	$row->{$kRebalShares} = $transaction->shares();
	$row->{$kRebalAmount} = $transaction->amount();
    }
    $row->{$kRebalReason} = $reason;
    $row->{$kRebalUnallocated} = $self->unallocated();
    $row->{$kRebalValue} = $self->value();
    foreach my $acct_name (keys %{ $self->accounts() }) {
	my $acct = $self->accounts()->{$acct_name};
	if ( $acct->value() > $gZero && $acct->fixed_size() ) {
	    my $key = sprintf("unalloc %s", $acct->name());
	    $row->{$key} = $acct->unallocated();
	}
	foreach my $symbol (keys %{ $acct->holdings() }) {
	    my $key = &holdingKey($symbol, $acct_name);
	    my $holding = $acct->holdings()->{$symbol};
	    $row->{$key} = $holding->value();
	}
    }
    &Util::printHashToCsv($row,
			  $column_headers,
			  undef, $csv, $raS);
}

sub printRebalanceCsvFile
{
    my($self,
       $OutDir,        # Output directory
       ) = @_;

    # Need all these fields defined.
    return unless
	defined($self->assetAllocation())
	&& defined($self->holdings())
	&& defined($self->accounts());
    
    my $fname = $OutDir . '/' .
	$self->name() . $time{'-yyyy-mm-dd'} . '.csv';

    open my $io, ">", $fname or die "$fname: $!";
    print "  Writing $fname\n";
    my $csv = Text::CSV_XS->new;

    my @S;
    $self->printRebalanceCsvString(\@S, $csv);
    print $io join("\n",@S), "\n";
    close $io;
}

1;
