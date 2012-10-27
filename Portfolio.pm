#!/bin/perl

# A portfolio is a collection of holdings or accounts.

package Portfolio;

use Account;
use AssetAllocation;
use AssetCategory;
use Finance::Math::IRR;
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

# Use a single, marginal tax rate.
my $gFedTaxRate = 0.35;
my $gStateTaxRate = 0.094;

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
	'van-goog-401k',
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
my $kCatROI = 'ROI';  # Return
my $kCatIRR = 'IRR';  # Internal Rate of Return
my $kCatAllocation = 'Allocation';
my $kCatCurrentWeight = 'Current Weight';
my $kCatDifference = 'Difference';
my $kCatDiffPercent = 'Diff %';
my $kCatTargetValue = 'Target Value';
my $kCatHighDivTargetValue = 'High Div Target Value';  # Subtract holdings that can't move
# Sum of holdings in tax advantaged accounts in which at least one of the holdings in
# this category can be purchased.
my $kCatTaxAdvAcctSpace = 'Tax Advantaged Accts Space';
my $kCatYield = 'Yield';
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
my $kHoldROI = 'ROI';  # Return on Investment
my $kHoldIRR = 'IRR';  # Internal Rate of Return
my $kHoldTaxAdvantaged = 'Tax Advantaged';
my $kHoldYield = 'Yield';
my $kHoldTaxYield = 'Taxable Yield';
my $kHoldFedTax = 'Fed Tax/yr';  # If held in a taxable account
my $kHoldCaTax = 'Ca Tax/yr';  # If held in a taxable account
my $kHoldTax = 'Est Tax/yr';  # If held in a taxable account
my $kHoldIdealVal = 'Ideal Value';
my $kHoldTaxAdvAcctSpace = 'Tax Adv Accts Space';  # See the Cat definition.
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
my $kRebalSymbol = 'Ticker';
my $kRebalAccount = 'Account';
my $kRebalCategory = 'Category';
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

	# Total return (percent).
	_roi => shift,

	# Internal Rate of Return -- Annualized personal rate of return.
	_irr => shift,

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
sub roi { $_[0]->{_roi}; }
sub irr { $_[0]->{_irr}; }

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
		# $deb = 1 if ($symbol eq 'LSGLX');
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


#
#
#
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
    
    my $rh_symbols_done = $self->sellHighYieldInTaxableAccount();
    $self->rebalance($rh_symbols_done);

    $self->printRebalanceLinesString(
	$raS,
 	$csv);

    my $current_portfolio = $self;
    my $num_rebalance_steps = scalar(@{$self->{_rebalTrans}});
    if ($num_rebalance_steps > 0) {
	$current_portfolio =
	    $self->{_rebalTrans}->[$num_rebalance_steps-1]->portfolio();
    }

    $current_portfolio->{_perCatData} = {};
    $current_portfolio->{_perHoldingData} = {};
    $current_portfolio->analyzeHoldingsAgainstAllocations();
    push @{$raS}, "\n";
    $current_portfolio->printCategoryLinesString(
	$raS,
	$csv);
    $current_portfolio->printTickerLinesString(
	$raS,
	$csv);
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

# Returns (symbol, acct_name)
sub parseKey {
    my($key) = @_;
    return split('/', $key, 2);
}

sub taxAdjustedYield {
    my($ticker) = @_;

    # Adjust yield to reflect tax laws.  The key is the
    # amounts federally exempt and state exempt, which read
    # from the ticker-info spreadsheet.
    my $tax_adjust = 
	( (1 - $ticker->attribute('Fed Tax Exempt')) * $gFedTaxRate + 
	  (1 - $ticker->attribute('State Tax Exempt')) * $gStateTaxRate )
	/ ($gFedTaxRate + $gStateTaxRate);
    return $ticker->attribute('Yield') * $tax_adjust;
}

sub applyTransaction {
    my($self, $transaction) = @_;
    my $action = $transaction->action();
    my $symbol = $transaction->symbol();
    my $acct_name = $transaction->account();
    if (!defined($self->holding($symbol))) {
	my $holding = Holding->new(
	    $transaction->ticker(),
	    $self->account($transaction->account()),
	    );
	$self->{_holdings}->{$symbol} = $holding;
    }
    $self->holding($symbol)->applyTransaction($transaction);
    my $acct = $self->account($acct_name);
    my $amount_returned_to_portfolio = $acct->applyRebalanceTransaction($transaction);
    $self->{_unallocated} += $amount_returned_to_portfolio;
    $self->calculateValue();
}

sub analyzeHoldingsAgainstAllocations {
    my($self) = @_;
    if (!defined($self->{_value})) {
	$self->calculateValue();
    }

    # Cache the tax advantaged accounts.
    my $tax_advantaged_accts = {};
    foreach my $acct_name (keys %{ $self->accounts() }) {
	my $acct = $self->accounts()->{$acct_name};
	if ($acct->tax_advantaged()) {
	    $tax_advantaged_accts->{$acct_name} = $acct;
	}
    }

    my $total_portfolio_value = 0;
    my $total_alloc = 0;  # Just a sanity check
    my $excess_buy = 0;  # This is the sum of all the buys & sells proposed for rebalancing
    my $alloc = $self->{_assetAllocation};
    my $total_cash_in = 0.0;
    my $total_my_return = 0.0;
    my $total_returned_capital = 0.0;
    my $rh_total_cashflow = {};
    foreach my $cat_name (sort keys %{ $alloc->categories() }) {
	my $category_value = 0;
	my $category = $alloc->category($cat_name);
	my $raTickerSymbols = $category->symbols();
	my $alloc_value = $category->value() / 100.0;
	$total_alloc += $alloc_value;

	# Alloc symbols will be in order or desirability.
	my @owned_symbols;
	my @alloc_symbols;
	my $cat_yield = -1.0;
	my $cash_in = 0.0;
	my $my_return = 0.0;
	my $returned_capital = 0.0;
	my $rh_cashflow = {};
	foreach my $symbol (@{ $raTickerSymbols }) {
	    push @alloc_symbols, $symbol;
	    if (defined($self->holding($symbol))
		&& ($self->holding($symbol)->shares() > $gZero)) {
		$category_value += $self->holding($symbol)->value();
		$cash_in += $self->holding($symbol)->cashIn();
		$my_return += $self->holding($symbol)->myReturn();
		$returned_capital += $self->holding($symbol)->returnedCapital();
		$self->holding($symbol)->cashFlow($rh_cashflow);
		$total_cash_in += $self->holding($symbol)->cashIn();
		$total_my_return += $self->holding($symbol)->myReturn();
		$total_returned_capital += $self->holding($symbol)->returnedCapital();
		$self->holding($symbol)->cashFlow($rh_total_cashflow);
		push @owned_symbols, $symbol;
	    }
	    my $taxable_yield = &taxAdjustedYield(Ticker::getBySymbol($symbol));

	    # Change the definition of cat yield to be the optimal holding yield.
# 	    $cat_yield = $taxable_yield
# 		if ($taxable_yield > $cat_yield);
 	    $cat_yield = $taxable_yield if ($cat_yield < 0.0);
	}
	$total_portfolio_value += $category_value;
# 	$gDebug && printf("Category %s = %f, total %f\n",
# 			  $cat_name, $category_value,
# 			  $total_portfolio_value);
	my $alloc_symbols = join(",", @alloc_symbols);  # Order by desirability
	my $owned_symbols = join(",", sort @owned_symbols);

	next if $alloc_value == 0 && $category_value == 0;

	$self->{_perCatData}->{$cat_name} = {};
	my $cat_data = $self->{_perCatData}->{$cat_name};
	$cat_data->{$kCategory} = $cat_name;
	$cat_data->{$kCatAllocTickers} = $alloc_symbols;
	$cat_data->{$kCatOwnedTickers} = $owned_symbols;
	$cat_data->{$kCatConsolidate} = (scalar(@owned_symbols)>1);
	$cat_data->{$kCatValue} = $category_value;

	# Note: After a lot of debugging, I found that the category
	# IRR can differ from the individual holding IRR even if there
	# is only one holding.  Specifically, for LSGLX, there was
	# only a single holding with IRR of 6%, while the category IRR
	# was 5%.  The difference arose because the category contains
	# transactions for an old holding that was completely sold.
	# These were considered in the category IRR.  I can't decide
	# if that's the correct information.  I guess it gives a
	# better historical view of the category, so I will leave it.
	&computePersonalReturn(
	    $cash_in, \$cat_data->{$kCatROI}, $my_return,
	    &computeIRR($rh_cashflow, $category_value,
			$returned_capital, "Category $cat_name"),
	    \$cat_data->{$kCatIRR});

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
	$cat_data->{$kCatHighDivTargetValue} = $target_value;
	$cat_data->{$kCatYield} = $cat_yield;
	$cat_data->{$kCatTaxAdvAcctSpace} = 0.0;

	# See the definition of kCatTaxAdvAcctSpace for more comments.
	foreach my $acct_name (keys %{ $tax_advantaged_accts }) {
	    my $acct = $self->accounts()->{$acct_name};
	    if (defined $acct->allowed_tickers()) {
		my $isect = &Util::intersect(\@alloc_symbols, $acct->allowed_tickers());
		if (scalar @$isect) {
		    $cat_data->{$kCatTaxAdvAcctSpace} += $acct->value();
# 		    printf("Cat %s: possible to hold %.2f in tax adv acct %s\n",
# 			   $cat_name, $acct->value(), $acct_name);
		} else {
# 		    printf("Cat %s: can't be held in tax adv acct %s\n",
# 			   $cat_name, $acct_name);
		}
	    } else {
		$cat_data->{$kCatTaxAdvAcctSpace} += $acct->value();
	    }
	}
	
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

    # Compute ROI and IRR for the portfolio.
    &computePersonalReturn(
	$total_cash_in, \$self->{_roi}, $total_my_return,
	&computeIRR($rh_total_cashflow, $total_portfolio_value,
		    $total_returned_capital,
		    sprintf("Portfolio %s", $self->name())),
	\$self->{_irr});

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
	    &computePersonalReturn(
		$holding->cashIn(), \$hold_data->{$kHoldROI}, $holding->myReturn(),
		$holding->IRR(), \$hold_data->{$kHoldIRR});
	    $hold_data->{$kHoldTaxAdvantaged} =
		($acct->tax_advantaged()) ? $value : 0;
	    $totalTaxAdvantagedValue += $hold_data->{$kHoldTaxAdvantaged};

	    $hold_data->{$kHoldYield} = $ticker->attribute('Yield');
	    $hold_data->{$kHoldTaxYield} = &taxAdjustedYield($ticker);
	
	    my $vec = 0;
	    if (defined $self->assetAllocation()->symbols()->{$symbol}) {
		my $cat_name = $hold_data->{$kHoldCategory} = 
		    $self->assetAllocation()->symbols()->{$symbol}->name();
		my $cat_data = $self->{_perCatData}->{$cat_name};

		# If the holding has a captial loss then we don't want
		# to move it from a taxable to taxadvantaged account
		# because of weird IRS rules.  So, we reduce the
		# target value of this category to be used for moving
		# assets into tax advantaged accounts.
		if ($hold_data->{$kHoldGain} < 0 && !$acct->tax_advantaged()) {
		    $cat_data->{$kCatHighDivTargetValue} -= $value;
		}

		# Set ideal value to 0 unless this is the first symbol
		# in this asset category.  If it is the ideal symbol,
		# then set the value to the new rebalanced value if it
		# needs to be rebalanced.  Otherwise, the ideal value
		# is the current value.
		#
		# I don't think the ideal values are useful when
		# computed this simply because we might not be able to
		# use the ideal symbol and a given category may be
		# split among multiple holdings.
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

		# Use ideal values to compute the taxes.  Thinking is
		# that this will give best ordering because it
		# reflects what will be purchased.
		#
		# Municipal bonds are exempt from both state and fed
		# taxes.  Gov securities are exempt from state taxes.
		# A fund will have a % of gov securities, which is
		# used as %exempt-from-state-taxes.
		$hold_data->{$kHoldFedTax} =
		    $hold_data->{$kHoldIdealVal} * $hold_data->{$kHoldYield} *
		    (1 - $ticker->attribute('Fed Tax Exempt')) * $gFedTaxRate / 100.0;

		$hold_data->{$kHoldCaTax} =
		    $hold_data->{$kHoldIdealVal} * $hold_data->{$kHoldYield} *
		    (1 - $ticker->attribute('State Tax Exempt')) * $gStateTaxRate / 100.0;

		$hold_data->{$kHoldTax} =
		    $hold_data->{$kHoldFedTax} + $hold_data->{$kHoldCaTax};

		$hold_data->{$kHoldTaxAdvAcctSpace} = $cat_data->{$kCatTaxAdvAcctSpace};

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

    printf("Tax Advantaged Account Total Value is %f\n", $totalTaxAdvantagedValue);

    # Go through holdings by order of yield value and determine which
    # holdings should be in tax advantaged accounts based on the ideal
    # value of that holding.
    my $availableTaxAdvantagedValue = $totalTaxAdvantagedValue;
    foreach my $key (sort
		     { $self->{_perHoldingData}->{$b}->{$kHoldTaxYield}
		       <=> $self->{_perHoldingData}->{$a}->{$kHoldTaxYield} }
		     keys %{ $self->{_perHoldingData} }) {
	last if ($availableTaxAdvantagedValue < $gZero);
	my $hold_data = $self->{_perHoldingData}->{$key};

	# Don't mess with holdings that currently have capital loss,
	# since tax treatment is unfavorable.  In this case, don't
	# adjust availableValue either, since we won't put in a tax
	# advantaged account.
	my %categories_used;
	if ($hold_data->{$kHoldGain} >= 0) {
	    # Not tax advantaged but there is available space in tax
	    # advantaged accounts to make it so.
	    if ($hold_data->{$kHoldTaxAdvantaged} == 0) {
		$hold_data->{$kHoldBitVec} |= $HIGH_DIVIDEND_TAX;
		$hold_data->{$kHoldHighDiv} = 1;
	    }

	    # Reduce available account value whether it's already tax
	    # advantaged or not.  Use the smaller of amount possible
	    # to be held in tax advantaged accounts and (adjusted)
	    # target value from this asset allocation category and
	    # remember that we've seen this category already in case
	    # there are multiple holdings for this category.
	    my $cat_name = $hold_data->{$kHoldCategory};
	    my $cat_data = $self->{_perCatData}->{$cat_name};

	    if ( !defined($categories_used{$cat_name}) ) {
		my $amount = $cat_data->{$kCatHighDivTargetValue};
		if ($cat_data->{$kCatTaxAdvAcctSpace} < $amount) {
		    $amount = $cat_data->{$kCatTaxAdvAcctSpace};
		}
		$categories_used{$cat_name} = $amount;
		$availableTaxAdvantagedValue -= $amount;
		printf("High div %s: cat %s, amt %.2f, left %.2f\n",
		       $hold_data->{$kHoldKey}, $cat_name, $amount,
		       $availableTaxAdvantagedValue);
	    }
	}
    }
}

# Capture this logic in one place.
sub computePersonalReturn {
    my(
	$cash_in,
	$r_roi,
	$my_return,
	$irr,
	$r_irr,
	) = @_;

    if ($cash_in > 0) {
	$$r_roi = $my_return / $cash_in;
    } else {
	$$r_roi = 0;
    }
    if ($cash_in > 0 && defined $irr) {
	$$r_irr = $irr;
	# if the ROI is less than IRR, then IRR is less than a year
	# and not very useful.  So replace it.
	if ( abs($$r_roi) < abs($$r_irr) ) {
	    $$r_irr = $$r_roi;
	}
    } else {
	$$r_irr = 0;
    }
}

# Capture this logic in one place.
sub computeIRR {
    my(
	$rh_cashflow,
	$value,
	$returned_capital,
	$label,
	) = @_;

    # Compute IRR.  We need to add a last transaction that represents
    # selling the holding and recouping the value plus any additional
    # money we've made from it.
    my ($yyyy,$mm,$dd) = (localtime)[5,4,3];
    $yyyy += 1900;
    $mm++;
    my $date_string = sprintf("%04d-%02d-%02d", $yyyy, $mm, $dd);
    $rh_cashflow->{$date_string} = -1 * ($value + $returned_capital);
    printf("Cashflow for %s:\n", $label);
    foreach my $date (sort keys %{$rh_cashflow}) {
	printf("  %s => \$%.2f,\n", $date, $rh_cashflow->{$date});
    }
    my $irr = xirr(%{$rh_cashflow}, precision => 0.001);
    if ( defined $irr ) {
	printf("  xirr is %.2f%%\n", 100.0 * $irr);
    } else {
	printf("ERROR: xirr is undefined for %s\n", $label);
    }
    return $irr;
}

sub printCategoryLinesString {
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $csv,           # In: A CSV object if you want to reuse one.
	) = @_;

    my $column_headers = [$kCategory, $kCatAllocTickers,
			  $kCatOwnedTickers, $kCatValue,
			  $kCatROI, $kCatIRR,
			  $kCatAllocation, $kCatCurrentWeight,
			  $kCatDifference, $kCatDiffPercent,
			  $kCatTargetValue, $kCatTargetValueDiff,
			  $kCatHighDivTargetValue,
			  $kCatTaxAdvAcctSpace, $kCatYield,
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
    $totals->{$kCatROI} = $self->roi();
    $totals->{$kCatIRR} = $self->irr();
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
			   $kHoldROI, $kHoldIRR, $kHoldTaxAdvantaged,
			   $kHoldYield, $kHoldTaxYield,
			   $kHoldIdealVal, $kHoldFedTax, $kHoldCaTax,
			   $kHoldTax, $kHoldTaxAdvAcctSpace,
			   $kHoldBitVec, $kHoldIdeal, $kHoldOver,
			   $kHoldHighDiv, $kHoldCapLoss,
			   $kHoldConsolidate, ];

    push @{$raS}, "\n";
    &Util::printCsv($column_headers, $csv, $raS);

    # Now write it out
    foreach my $key (sort
		     { $self->{_perHoldingData}->{$b}->{$kHoldTaxYield}
		       <=> $self->{_perHoldingData}->{$a}->{$kHoldTaxYield} }
		     keys %{ $self->{_perHoldingData} }) {
	&Util::printHashToCsv($self->{_perHoldingData}->{$key},
			      $column_headers,
			      undef, $csv, $raS);
    }
}

# 
sub sellHighYieldInTaxableAccount {
    my($self) = @_;

    # Cache the tax advantaged accounts.
    my $tax_advantaged_accts = {};
    my $taxable_accts = {};
    my $totalTaxAdvantagedValue = 0;
    foreach my $acct_name (keys %{ $self->accounts() }) {
	my $acct = $self->accounts()->{$acct_name};
	if ($acct->tax_advantaged()) {
	    $tax_advantaged_accts->{$acct_name} = $acct;
	    $totalTaxAdvantagedValue += $acct->value();
	} else {
	    $taxable_accts->{$acct_name} = $acct;
	}
    }

    # This loop terminates early if there is no more space left in tax
    # advantaged accounts.
    my $availableTaxAdvantagedValue = $totalTaxAdvantagedValue;

    # Keeps track of new purchases and existing holdings so that they
    # are locked in place and can't be forced to be sold to make room
    # for some other holding.
    my $symbols_done = {};

    # Need to do most of the work with the current snapshot of the
    # portfolio as its being rebalanced.  We make a deep copy at each
    # sell/buy, so this must point to the most recent deep copy.
    my $current_portfolio = $self;

    my $stop_after = 20;
    my $count = 0;
    
    # Go through portfolio categories from highest to lowest
    # catMaxYield, which is the highest tax adjusted yield of all
    # possible holdings in the category.  Should we just use the yield
    # of the optimal holding?  Or of holdings we actually own?
    foreach my $cat_name (sort
		     { $self->{_perCatData}->{$b}->{$kCatYield}
		       <=> $self->{_perCatData}->{$a}->{$kCatYield} }
		     keys %{ $self->{_perCatData} }) {
	my $cat_data = $self->{_perCatData}->{$cat_name};
	my $target_value = $cat_data->{$kCatTargetValue};
	printf("High Yield Buy \$%.2f of %s (taxable yield %.2f)\n",
	       $target_value, $cat_name, $cat_data->{$kCatYield});
    
	# Make a list of the holdings for this category.  We may end up
	# selling these.
	my $alloc = $self->{_assetAllocation};
	my $category = $alloc->category($cat_name);
	my $raTickerSymbols = $category->symbols();
	my $amount_held = 0.0;

	# key is holding key, value is holding value.  If value is 0,
	# then we've already sold this holding.
	my $rh_holdings_to_maybe_sell = {};
	foreach my $cat_symbol (@{ $raTickerSymbols }) {
	    foreach my $acct_name (keys %{ $current_portfolio->accounts() }) {
		my $acct = $current_portfolio->accounts()->{$acct_name};
		foreach my $acct_symbol (keys %{ $acct->holdings() }) {
		    next unless ($acct_symbol eq $cat_symbol);
		    my $key = &holdingKey($acct_symbol, $acct_name);
		    my $holding = $acct->holding($acct_symbol);
		    my $value = $holding->value();
		    next if ($value <= $gZero);
		    $amount_held += $rh_holdings_to_maybe_sell->{$key} = $value;
		    printf("Maybe sell \$%.2f of %s\n", $value, $key);
		}
	    }
	}

	# If we are already own too much in this category, sell some
	# of the holdings.
	my $extra_to_buy = 0.0;
	my $ra_symbol_sell_order = [ reverse @{ $raTickerSymbols } ];
	if ( $target_value < $amount_held ) {
	    my $amount_to_sell = $amount_held - $target_value;
	    printf("Sell \$%.2f to rebalance\n", $amount_to_sell);
	    my $reason = sprintf("Sell \$%.2f from HY Category \"%s\"", $amount_to_sell, $cat_name);
	    my $remaining_amount =
		$self->sellHighYieldHoldings(\$current_portfolio,
					     $amount_to_sell,
					     $ra_symbol_sell_order,
					     $rh_holdings_to_maybe_sell,
					     $reason);
	    ($remaining_amount > $gZero)
		&& print "Error: Can't sell enough (initially).\n";
	} else {
	    # If we don't own enough of this category, compute how
	    # much more we'll need to buy.  Below, the code forces
	    # sales from the targeted accounts that cover whatever we
	    # end up buying.
	    $extra_to_buy = $target_value - $amount_held;
	    printf("Increase holdings by \$%.2f to rebalance\n", $extra_to_buy);
	}

	# Subtract taxable holdings in this category that we'd be
	# selling with a capital loss. The IRS doesn't allow tax
	# benefit for this sale, so we don't want to do it.
	# We can use $self and _perHoldingData because we never sell
	# these holdings
	foreach my $key (keys %{ $rh_holdings_to_maybe_sell } ) {
	    my ($symbol, $acct_name) = &parseKey($key);
	    my $acct = $current_portfolio->account($acct_name);
	    my $holding = $acct->holding($symbol);
	    if ($holding->gain() < 0 && !$acct->tax_advantaged()) {
		$target_value -= $holding->value();
		$cat_data->{$kCatBuy} += $holding->value();
		$availableTaxAdvantagedValue -= $holding->value();
		printf("  Reduce Buy to \$%.2f because holding %s has capital loss\n",
		       $target_value, $key);

		# Remove this holding from the list of
		# holdings in this category we might sell.
		$rh_holdings_to_maybe_sell->{$key} = 0.0;
	    }
	}

	next if ($target_value < $gZero);
	
    	my $category = $alloc->category($cat_name);
	my $raTickerSymbols = $category->symbols();

	foreach my $symbol (@{ $raTickerSymbols }) {
	    printf("  Need to buy \$%.2f, consider symbol %s\n",
		   $target_value, $symbol);

	    # Subtract holdings of this symbol already owned in tax
	    # advantaged accounts.  This relies on going through the
	    # symbols in preferred order.  Preferred symbols can
	    # replace less favored ones, but not vice versa.
	    foreach my $acct_name (keys %{ $tax_advantaged_accts }) {
		my $acct = $current_portfolio->account($acct_name);
		foreach my $acct_symbol (keys %{ $acct->holdings() }) {
		    next unless ($acct_symbol eq $symbol);
		    my $key = &holdingKey($acct_symbol, $acct_name);
		    my $holding = $acct->holding($symbol);
		    if ($holding->value() > $gZero) {
			$target_value -= $holding->value();
			$cat_data->{$kCatBuy} += $holding->value();
			$availableTaxAdvantagedValue -= $holding->value();
			printf("    Reduce Buy to \$%.2f -> already hold %s\n",
			       $target_value, $key);

			# Remove this holding from the list of
			# holdings in this category we might sell.
			$rh_holdings_to_maybe_sell->{$key} = 0.0;
		    }
		}
	    }

	    # Now add it to the symbols we've done before we process
	    # it so that we won't sell any holdings of this symbol.
	    # They are now locked.
	    $symbols_done->{$symbol} = 1;

	    # Don't early exit from this loop because we want to add
	    # all the symbols to symbols_done.
	    next if ($target_value < $gZero);

	    # Try to buy
	    my $rh_buys =
		$self->tryToBuy($current_portfolio, $symbol, $target_value,
				$symbols_done, $tax_advantaged_accts);

	    # Handle the buy(s).
	    foreach my $acct_name (keys %{$rh_buys}) {
		my $amount = $rh_buys->{$acct_name};

		printf("    Buy \$%.2f in %s\n", $amount, $acct_name);
		
		# Part 1: This should be a move of assets from the allocated
		# amount for this category.  Use up any "extra" cash
		# first.
		if ( $extra_to_buy > $amount ) {
		    $extra_to_buy -= $amount;
		    printf("  Doing buy from extra_to_buy (\$%.2f remains)\n", $extra_to_buy);
		} else {
		    # Now sell enough existing holdings in this category
		    # to match the buy.  This is effectively a move from
		    # these accounts to the account to buy in.  Use the
		    # same order as above when we had too much in this
		    # category.
		    my $reason = sprintf("Move HY Cat \"%s\"", $cat_name);
		    my $remaining_amount =
			$self->sellHighYieldHoldings(\$current_portfolio,
						     $amount - $extra_to_buy,
						     $ra_symbol_sell_order,
						     $rh_holdings_to_maybe_sell,
						     $reason);
		    if ($remaining_amount > $gZero) {
			printf("Error: Can't sell enough %s for buy in acct %s (\$%.2f remains)\n",
			       $symbol, $acct_name, $remaining_amount);
			print $remaining_amount, "\n";
		    }
		    $extra_to_buy = 0.0;
		}

		# Part 2: Now we have to make sure there is actually
		# enough room in the to make the real buy.  This will
		# use any unallocated funds from account, and then
		# sell unrelated holdings in the tax advantaged
		# account to make room.  Selling these unrelated
		# holdings will likely leave us short in some other
		# asset category.
		my $remaining_amount;
		$self->sellHoldingsToMakeRoom(\$current_portfolio, $acct_name, $amount,
					      $symbols_done, \$remaining_amount,
					      "Make Room in Acct $acct_name for $symbol");
		($remaining_amount > $gZero)
		    && print "Error: Can't make enough room in acct $acct_name\n";

		# Part 3: Actually buy the new holding.
		$current_portfolio =
		    $self->rebalanceBuy($symbol, $acct_name, $amount,
					"HY Cat \"$cat_name\" to Tax Adv Acct $acct_name");

		$target_value -= $amount;
		$cat_data->{$kCatBuy} += $amount;
		$availableTaxAdvantagedValue -= $amount;
	    }
	}
	printf("Remaining in tax advantaged accounts = \$%.2f\n",
	       $availableTaxAdvantagedValue);
	$count++;
	last if ($count >= $stop_after);
	last if ($availableTaxAdvantagedValue <= $gZero);
    }
    return $symbols_done;
}

# Sell $amount of the holdings to maybe sell.  Start in taxable
# accounts first, going least desireable symbol to most.  Then tax
# advantaged.
sub sellHighYieldHoldings {
    my($self,
       $r_current_portfolio,
       $total_amount,  # Need to generate this amount of cash
       $ra_symbol_sell_order,  # Choose holdings using this symbol order
       $rh_holdings_to_maybe_sell,  # Sell these holdings
       $reason,                     # Explanation
	) = @_;
    
    my $remaining_amount =
	$self->sellHighYieldHoldingsFromTaxableAccounts(
	    $r_current_portfolio, $total_amount, $ra_symbol_sell_order,
	    $rh_holdings_to_maybe_sell, $reason);

    if ($remaining_amount > 0.0) {
	$remaining_amount =
	    $self->sellHighYieldHoldingsFromTaxAdvantagedAccounts(
		$r_current_portfolio, $remaining_amount, $ra_symbol_sell_order,
		$rh_holdings_to_maybe_sell, $reason);
    }
    return $remaining_amount;
}

# Returns portion of $total_amount that remains unsold.
sub sellHighYieldHoldingsFromTaxableAccounts {
    my($self,
       $r_current_portfolio,
       $total_amount,               # Need to generate this amount of cash
       $ra_symbol_sell_order,       # Choose holdings using this symbol order
       $rh_holdings_to_maybe_sell,  # Sell these holdings
       $reason,                     # Explanation
	) = @_;

    return $total_amount if ($total_amount <= $gZero);
    my $remaining_amount = $total_amount;
    foreach my $acct_name (keys %{$$r_current_portfolio->accounts()}) {
	my $acct = $$r_current_portfolio->accounts()->{$acct_name};
	next if ($acct->tax_advantaged());
	foreach my $cat_symbol (@{$ra_symbol_sell_order}) {
	    foreach my $acct_symbol (keys %{ $acct->holdings() }) {
		next unless ($acct_symbol eq $cat_symbol);
		my $acct_key = &holdingKey($acct_symbol, $acct_name);
		next unless defined $rh_holdings_to_maybe_sell->{$acct_key};
		my $holding = $acct->holding($acct_symbol);
		my $sell_amount =
		    &Util::minimum($holding->value(),$rh_holdings_to_maybe_sell->{$acct_key});
		my $sell_amount = &Util::minimum($remaining_amount, $sell_amount);
		if ($sell_amount > $gZero) {
		    $$r_current_portfolio =
			$self->rebalanceSale($acct_symbol, $acct_name, $sell_amount, $reason);
		    $remaining_amount -= $sell_amount;
		    return $remaining_amount if ($remaining_amount <= $gZero);
		}
	    }
	}
    }
    return $remaining_amount;
}

# Returns portion of $total_amount that remains unsold.  For tax
# advantaged, go smallest to largest, least desireable to most.
sub sellHighYieldHoldingsFromTaxAdvantagedAccounts {
    my($self,
       $r_current_portfolio,
       $total_amount,               # Need to generate this amount of cash
       $ra_symbol_sell_order,       # Choose holdings using this symbol order
       $rh_holdings_to_maybe_sell,  # Sell these holdings
       $reason,                     # Explanation
	) = @_;

    return $total_amount if ($total_amount <= $gZero);
    my $remaining_amount = $total_amount;
    foreach my $acct_name (sort { $$r_current_portfolio->account($a)->value()
				      <=> $$r_current_portfolio->account($b)->value() }
			   keys %{ $$r_current_portfolio->accounts() }) {
	my $acct = $$r_current_portfolio->accounts()->{$acct_name};
	next unless ($acct->tax_advantaged());
	foreach my $cat_symbol (@{$ra_symbol_sell_order}) {
	    foreach my $acct_symbol (keys %{ $acct->holdings() }) {
		next unless ($acct_symbol eq $cat_symbol);
		my $acct_key = &holdingKey($acct_symbol, $acct_name);
		next unless defined $rh_holdings_to_maybe_sell->{$acct_key};
		my $holding = $acct->holding($acct_symbol);
		my $sell_amount =
		    &Util::minimum($holding->value(),$rh_holdings_to_maybe_sell->{$acct_key});
		my $sell_amount = &Util::minimum($remaining_amount, $sell_amount);
		if ($sell_amount > $gZero) {
		    $$r_current_portfolio =
			$self->rebalanceSale($acct_symbol, $acct_name, $sell_amount, $reason);
		    $remaining_amount -= $sell_amount;
		    return $remaining_amount if ($remaining_amount <= $gZero);
		}
	    }
	}
    }
    return $remaining_amount;
}

sub rebalance {

    # Symbols_done needs to carry forward here.
    my($self, $rh_symbols_done) = @_;

    printf("Rebalance: Symbols done: %s\n",
	   join(", ", sort keys %{$rh_symbols_done}));

    # Need to do most of the work with the current snapshot of the
    # portfolio as its being rebalanced.  We make a deep copy at each
    # sell/buy, so this must point to the most recent deep copy.
    my $current_portfolio = $self;
    my $num_rebalance_steps = scalar(@{$self->{_rebalTrans}});
    if ($num_rebalance_steps > 0) {
	$current_portfolio =
	    $self->{_rebalTrans}->[$num_rebalance_steps-1]->portfolio();
    }

    # Stop the loop early for debugging.
    my $stop_after = 20;
    my $count = 0;
    
    # Go through portfolio categories from highest to lowest
    # catMaxYield, which is the highest tax adjusted yield of all
    # possible holdings in the category.  Should we just use the yield
    # of the optimal holding?  Or of holdings we actually own?
    #
    # Sort order still matters here, even though we did the tax
    # advantaged stuff already.
    foreach my $cat_name (sort
		     { $self->{_perCatData}->{$b}->{$kCatYield}
		       <=> $self->{_perCatData}->{$a}->{$kCatYield} }
		     keys %{ $self->{_perCatData} }) {
	my $cat_data = $self->{_perCatData}->{$cat_name};
	my $target_value = $cat_data->{$kCatTargetValue};
	printf("Rebalance Buy \$%.2f of %s (previously bought \$%.f)\n",
	       $target_value, $cat_name, $cat_data->{$kCatBuy});
    
	# Make a list of the holdings for this category.  We may end up
	# selling these.
	my $alloc = $self->{_assetAllocation};
	my $category = $alloc->category($cat_name);
	my $raTickerSymbols = $category->symbols();
	my $amount_held = 0.0;

	# key is holding key, value is holding value.  If value is 0,
	# then we've already sold this holding.
	my $rh_holdings_to_maybe_sell = {};
	foreach my $cat_symbol (@{ $raTickerSymbols }) {
	    foreach my $acct_name (keys %{ $current_portfolio->accounts() }) {
		my $acct = $current_portfolio->accounts()->{$acct_name};
		foreach my $acct_symbol (keys %{ $acct->holdings() }) {
		    next unless ($acct_symbol eq $cat_symbol);
		    my $key = &holdingKey($acct_symbol, $acct_name);
		    my $holding = $acct->holding($acct_symbol);
		    my $value = $holding->value();
		    next if ($value <= $gZero);
		    $amount_held += $rh_holdings_to_maybe_sell->{$key} = $value;
		    printf("Maybe sell \$%.2f of %s\n", $value, $key);
		}
	    }
	}

	# If we are already own too much in this category, sell some
	# of the holdings.
	my $extra_to_buy = 0.0;
	my $ra_symbol_sell_order = [ reverse @{ $raTickerSymbols } ];
	if ( $target_value < $amount_held ) {
	    my $amount_to_sell = $amount_held - $target_value;
	    printf("Sell \$%.2f to rebalance\n", $amount_to_sell);
	    my $reason = sprintf("Sell \$%.2f from Category \"%s\"", $amount_to_sell, $cat_name);
	    my $remaining_amount =
		$self->sellHighYieldHoldings(\$current_portfolio,
					     $amount_to_sell,
					     $ra_symbol_sell_order,
					     $rh_holdings_to_maybe_sell,
					     $reason);
	    ($remaining_amount > $gZero)
		&& print "Error: Can't sell enough (initially).\n";
	} else {
	    # If we don't own enough of this category, compute how
	    # much more we'll need to buy.  Below, the code forces
	    # sales from the targeted accounts that cover whatever we
	    # end up buying.
	    $extra_to_buy = $target_value - $amount_held;
	    printf("Increase holdings by \$%.2f to rebalance\n", $extra_to_buy);
	}

	# Do a pre-pass to subtract all holdings in this category
	# that we just bought.
	foreach my $key (keys %{ $rh_holdings_to_maybe_sell } ) {
	    my ($symbol, $acct_name) = &parseKey($key);
	    my $acct = $current_portfolio->account($acct_name);
	    my $holding = $acct->holding($symbol);
	    if (defined($rh_symbols_done->{$symbol})) {
		# Bought during this rebalancing, so it's locked.
		my $amount = $holding->value();
		$target_value -= $amount;
		printf("  Just bought \$%.2f of %s\n",
		       $amount, $key);

		# Remove this holding from the list of
		# holdings in this category we might sell.
		$rh_holdings_to_maybe_sell->{$key} = 0.0;
	    }
	}
	next if ($target_value < $gZero);

    	my $category = $alloc->category($cat_name);
	my $raTickerSymbols = $category->symbols();

	foreach my $symbol (@{ $raTickerSymbols }) {
	    printf("  Need to buy \$%.2f, consider symbol %s\n",
		   $target_value, $symbol);

	    # Subtract holdings of this symbol already owned, but not
	    # in symbols_done.  This relies on going through the
	    # symbols in preferred order.  Preferred symbols can
	    # replace less favored ones, but not vice versa.
	    foreach my $acct_name (keys %{ $self->accounts() }) {
		my $acct = $current_portfolio->account($acct_name);
		foreach my $acct_symbol (keys %{ $acct->holdings() }) {
		    next unless ($acct_symbol eq $symbol);
		    next if (defined($rh_symbols_done->{$symbol}));
		    my $key = &holdingKey($acct_symbol, $acct_name);
		    my $holding = $acct->holding($symbol);
		    if ($holding->value() > $gZero) {
			$target_value -= $holding->value();
			$cat_data->{$kCatBuy} += $holding->value();
			printf("    Reduce Buy to \$%.2f -> already hold %s\n",
			       $target_value, $key);

			# Remove this holding from the list of
			# holdings in this category we might sell.
			$rh_holdings_to_maybe_sell->{$key} = 0.0;
		    }
		}
	    }

	    # Now add it to the symbols we've done before we process
	    # it so that we won't sell any holdings of this symbol.
	    # They are now locked.
	    $rh_symbols_done->{$symbol} = 1;

	    # Don't early exit from this loop because we want to add
	    # all the symbols to symbols_done.
	    next if ($target_value < $gZero);

	    # Try to buy
	    my $rh_buys =
		$self->tryToBuy($current_portfolio, $symbol, $target_value,
				$rh_symbols_done, $self->accounts());

	    # Handle the buy(s).
	    foreach my $acct_name (keys %{$rh_buys}) {
		my $amount = $rh_buys->{$acct_name};

		printf("    Buy \$%.2f in %s\n", $amount, $acct_name);
		
		# Part 1: This should be a move of assets from the allocated
		# amount for this category.  Use up any "extra" cash
		# first.
		if ( $extra_to_buy > $amount ) {
		    $extra_to_buy -= $amount;
		    printf("  Doing buy from extra_to_buy (\$%.2f remains)\n", $extra_to_buy);
		} else {
		    # Now sell enough existing holdings in this category
		    # to match the buy.  This is effectively a move from
		    # these accounts to the account to buy in.  Use the
		    # same order as above when we had too much in this
		    # category.
		    my $remaining_amount =
			$self->sellHighYieldHoldings(\$current_portfolio,
						     $amount - $extra_to_buy,
						     $ra_symbol_sell_order,
						     $rh_holdings_to_maybe_sell,
						     "Move Cat \"$cat_name\"");
		    if ($remaining_amount > $gZero) {
			printf("Error: Can't sell enough %s for buy in acct %s (\$%.2f remains)\n",
			       $symbol, $acct_name, $remaining_amount);
			print $remaining_amount, "\n";
		    }
		    $extra_to_buy = 0.0;
		}

		# Part 2: Now we have to make sure there is actually
		# enough room in the to make the real buy.  This will
		# use any unallocated funds from account, and then
		# sell unrelated holdings in the tax advantaged
		# account to make room.  Selling these unrelated
		# holdings will likely leave us short in some other
		# asset category.
		my $remaining_amount;
		my $acct = $current_portfolio->account($acct_name);
		if ($acct->fixed_size()) {
		    $self->sellHoldingsToMakeRoom(\$current_portfolio, $acct_name, $amount,
						  $rh_symbols_done, \$remaining_amount,
						  "Make Room in Acct $acct_name for $symbol");
		    ($remaining_amount > $gZero)
			&& print "Error: Can't make enough room in acct $acct_name\n";
		     }

		# Part 3: Actually buy the new holding.
		$current_portfolio =
		    $self->rebalanceBuy($symbol, $acct_name, $amount,
					sprintf("Increase Cat \"%s\" by \$%.2f", $cat_name, $amount));

		$target_value -= $amount;
		$cat_data->{$kCatBuy} += $amount;
	    }
	}
	$count++;
	last if ($count >= $stop_after);
    }
}

# returns hash reference to $buys (defined below).
sub tryToBuy {
    my($self, $current_portfolio, $symbol,
       $amount, $rh_symbols_done, $rh_accts) = @_;

    my $acct_capacities = {};  # Hash by acct name
    my $buys = {};  # Hash by acct name, value is amount to buy

    # Compute current account capacity for this specific symbol as a
    # prepass.
    my $total_available_capacity = 0.0;
    my $accts_that_can_hold_entire_buy = [];
    my $accts_holding_this_symbol = [];
    my $accts_previously_holding_symbol = [];
    foreach my $acct_name (keys %{$rh_accts}) {
	my $capacity = $self->acctCapacityForSymbol(
	    $current_portfolio, $acct_name, $symbol, $rh_symbols_done,
	    $accts_holding_this_symbol, $accts_previously_holding_symbol,
	    $amount);
	$acct_capacities->{$acct_name} = $capacity;
	$total_available_capacity += $capacity;
	push @{$accts_that_can_hold_entire_buy}, $acct_name
	    if ($capacity >= $amount);
	printf("    Acct %s can hold \$%.2f of %s\n",
	       $acct_name, $capacity, $symbol);
    }

    if ($total_available_capacity <= $gZero) {
	printf("    No available capacity\n");
	return $buys;
    }

    # See if an account with an existing holding can hold the entire amount.
    print("    Accts that can hold entire amount:",
	  join(", ", @$accts_that_can_hold_entire_buy), "\n");
    print("    Accts holding this symbol:",
	  join(", ", @$accts_holding_this_symbol), "\n");
    print("    Accts previously holding this symbol:",
	  join(", ", @$accts_previously_holding_symbol), "\n");
    my $current_and_big_enough = &Util::intersect($accts_that_can_hold_entire_buy,
						  $accts_holding_this_symbol);
    my $previous_and_big_enough = &Util::intersect($accts_that_can_hold_entire_buy,
						   $accts_previously_holding_symbol);
    print("    Current and big enough:",
	  join(", ", @$current_and_big_enough), "\n");
    print("    Previous and big enough:",
	  join(", ", @$previous_and_big_enough), "\n");
    if (scalar(@$current_and_big_enough) > 0) {
	# Select by priority
	my @acct_names = sort { $current_portfolio->accounts->{$a}->priority()
				    <=> $current_portfolio->accounts->{$b}->priority() }
	                 @$current_and_big_enough;
	$buys->{$acct_names[0]} = $amount;
	printf("    Buy from %s: highest priority account with existing holding\n",
	       $acct_names[0]);
    } elsif (scalar(@$previous_and_big_enough) > 0) {
	# Select by priority
	my @acct_names = sort { $current_portfolio->accounts->{$a}->priority()
				    <=> $current_portfolio->accounts->{$b}->priority() }
	                 @$previous_and_big_enough;
	$buys->{$acct_names[0]} = $amount;
	printf("    Buy from %s: highest priority account with previous holding\n",
	       $acct_names[0]);
    } elsif (scalar(@$accts_that_can_hold_entire_buy)) {
	# Select by priority
	my @acct_names = sort { $current_portfolio->accounts->{$a}->priority()
				    <=> $current_portfolio->accounts->{$b}->priority() }
	                 @$accts_that_can_hold_entire_buy;
	$buys->{$acct_names[0]} = $amount;
	printf("    Buy from %s: highest priority account that can hold it\n",
	       $acct_names[0]);
    } else {

	print("    Buy from multiple accounts:\n");

	# May not be able to buy the entire amount, so adjust the amount
	# we will buy to match total available.
	if ($amount > $total_available_capacity) {
	    $amount = $total_available_capacity;
	    printf("    Adjust buy to \$%.2f total capacity\n", $amount);
	}

	# Use accounts with existing holdings first.  Start with
	# largest first to minimize the number of accounts.
	my $amount_remaining_to_buy = $amount;
	foreach my $acct_name (sort { $acct_capacities->{$b}
				      <=> $acct_capacities->{$a} }
			       @$accts_that_can_hold_entire_buy) {
	    return $buys if ($amount_remaining_to_buy <= $gZero);
	    my $buy_amount = &Util::minimum($acct_capacities->{$acct_name}, $amount_remaining_to_buy);
	    $buys->{$acct_name} = $buy_amount;
	    $amount_remaining_to_buy -= $buy_amount;
	    printf("      Buy \$%.2f from %s (\$%.2f remaining)\n",
		   $buy_amount, $acct_name, $amount_remaining_to_buy);
	    # Set to zero since if we didn't use all the money, then
	    # the amount remaining to buy == 0
	    $acct_capacities->{$acct_name} = 0.0;
	}

	# Buy the remainder starting with biggest accounts.
	foreach my $acct_name (sort { $acct_capacities->{$b}
				      <=> $acct_capacities->{$a} }
			       keys %{$acct_capacities} ) {
	    return $buys if ($amount_remaining_to_buy <= $gZero);
	    my $buy_amount = &Util::minimum($acct_capacities->{$acct_name}, $amount_remaining_to_buy);
	    $buys->{$acct_name} = $buy_amount;
	    $amount_remaining_to_buy -= $buy_amount;
	    printf("      Buy \$%.2f from %s\n", $buy_amount, $acct_name);
	    # Set to zero since if we didn't use all the money, then
	    # the amount remaining to buy == 0
	    $acct_capacities->{$acct_name} = 0.0;
	}
    }
    return $buys;
}

# Returns dollar amount this account can hold of this symbol, up to
# buy amount.
sub acctCapacityForSymbol {
    my($self, $current_portfolio, $acct_name, $symbol,
       $rh_symbols_done, $ra_symbol_found, $ra_original_symbol_found,
       $buy_amount) = @_;

    # Can this account hold this symbol at all?
    my $acct = $current_portfolio->accounts()->{$acct_name};
    if (defined $acct->allowed_tickers()) {
	my $isect = &Util::intersect([$symbol], $acct->allowed_tickers());
	if (0 == scalar(@$isect)) {
	    printf("      Symbol %s: not allowed in adv acct %s\n",
		   $symbol, $acct_name);
	    return 0.0;
	}
    } elsif (defined $acct->disallowed_tickers()) {
	my $isect = &Util::intersect([$symbol], $acct->disallowed_tickers());
	if (0 < scalar(@$isect)) {
	    printf("      Symbol %s: disallowed in adv acct %s\n",
		   $symbol, $acct_name);
	    return 0.0;
	}
    }

    # Start with the total account value.  Includes unallocated value.
    my $amount = $acct->value();
    printf("      Acct %s: value \$%.2f\n",
	   $acct_name, $amount);
    return $amount if ($amount < $gZero);
    
    # Subtract previous buys/locked assets.
    my @symbols_done = keys %{$rh_symbols_done};
    printf("    acctCapacity for %s, Symbols done: %s\n",
	   $symbol, join(", ", @symbols_done));
    foreach my $held_symbol (keys %{ $acct->holdings() }) {

	next if ($acct->holding($held_symbol)->value() < $gZero);

	printf("      \$%.2f of %s is in acct %s\n",
	       $acct->holding($held_symbol)->value(), $held_symbol,
	       $acct_name);

	if (defined($rh_symbols_done->{$held_symbol})) {
	    # Bought during this rebalancing, so it's locked.
	    $amount -= $acct->holding($held_symbol)->value();
	    printf("        \$%.2f in acct %s is locked in %s\n",
		   $acct->holding($held_symbol)->value(),
		   $acct_name, $held_symbol);
	}
	if ($held_symbol eq $symbol) {
	    push @$ra_symbol_found, $acct_name;
	}
    }

    # See if this symbol was held in the original portfolio.
    my $acct = $self->accounts()->{$acct_name};
    foreach my $held_symbol (keys %{ $acct->holdings() }) {
	next if ($acct->holding($held_symbol)->value() < $gZero);
	printf("      \$%.2f of %s was originally in acct %s\n",
	       $acct->holding($held_symbol)->value(), $held_symbol,
	       $acct_name);
	if ($held_symbol eq $symbol) {
	    push @$ra_original_symbol_found, $acct_name;
	}
    }
    if ($acct->fixed_size()) {
	return &Util::minimum($amount, $buy_amount);
    } else {
	# If the account doesn't have fixed size, it can hold the
	# entire amount.  Still need to do loop above to compute out
	# parameters.
	return $buy_amount;
    }
}

# Returns 1 if holding in this account is locked, e.g. because it was just
# purchased in this round of rebalancing.
sub symbolLocked {
    my($self, $symbol, $ra_symbols_done) = @_;

    my $isect = &Util::intersect([$symbol], $ra_symbols_done);
    if (scalar @$isect) {
	return 1;
    }
    return 0;
}

# Sell $amount of the holdings in acct $acct_name.
sub sellHoldingsToMakeRoom {
    my($self,
       $r_current_portfolio,
       $acct_name,
       $total_amount,
       $rh_symbols_done,
       $r_remaining_amount,
       $reason,                     # Explanation
	) = @_;
    
    return $total_amount if ($total_amount <= $gZero);
    $$r_remaining_amount = $total_amount;
    my $acct = $$r_current_portfolio->account($acct_name);

    # Start with the smallest taxable yield on the theory this might
    # be in the correct account already.
    foreach my $symbol (sort { &taxAdjustedYield($acct->holding($a)->ticker())
				   <=> &taxAdjustedYield($acct->holding($b)->ticker()) }
			keys %{ $acct->holdings() }) {

	# skip symbols that are locked because we purchased them as
	# part of the rebalancing.
	next if defined($rh_symbols_done->{$symbol});

	my $key = &holdingKey($symbol, $acct_name);
	my $holding = $acct->holdings()->{$symbol};
	my $ticker = $holding->ticker();
	next if ($ticker->skip());
	next if ($holding->value() < $gZero);
	my $sell_amount = &Util::minimum($$r_remaining_amount, $holding->value());
	$$r_current_portfolio = $self->rebalanceSale($symbol, $acct_name, $sell_amount, $reason);
	$$r_remaining_amount -= $sell_amount;
	last if ($$r_remaining_amount <= $gZero);
    }
}

# Utility for all rebalance buy transactions.
sub rebalanceBuy {
    my($self,
       $symbol,
       $acct_name,
       $amount,     
       $reason,     # Just a documentation string.
	) = @_;

    my $deep_copy = $self->clonePortfolioForTransaction();

    # Figure out all the fields needed.
    my $ticker = &Ticker::getBySymbol($symbol);
    if ($ticker->skip()) {
	printf("Error: Trying to sell skipped symbol %s\n", $symbol);
	die();
    }
    my $price = $ticker->attribute('Price');
    my $shares = $amount / $price;

    printf("      Buy %s (%s) Acct %s: %f shares @ \$%f = \$%.2f\n",
	   $symbol, $reason, $acct_name, $shares, $price, $amount);
    my $rebal_trans = RebalTran::newBuy(
	$reason,
	$ticker->name(),
	$ticker,
	$symbol,
	$acct_name,
	$price,
	$shares,
	$deep_copy);
    $deep_copy->applyTransaction($rebal_trans->transaction());
    push @{$self->{_rebalTrans}}, $rebal_trans;
    return $deep_copy;
}

# Utility for all rebalance sale transactions.
sub rebalanceSale {
    my($self,
       $symbol,
       $acct_name,  
       $amount,     # If undef, then sell all.
       $reason,     # Just a documentation string.
	) = @_;

    my $deep_copy = $self->clonePortfolioForTransaction();

    # Figure out all the fields needed.
    my $ticker = &Ticker::getBySymbol($symbol);
    if ($ticker->skip()) {
	printf("Error: Trying to sell skipped symbol %s\n", $symbol);
	die();
    }
    my $price = $ticker->attribute('Price');
    my $acct = $deep_copy->account($acct_name);
    my $holding = $acct->holding($symbol);
    my $shares = $holding->shares();
    if (defined($amount)) {
	$shares = $amount / $price;
    }
    printf("      Sell %s (%s) Acct %s: %f shares @ \$%f = \$%.2f\n",
	   $symbol, $reason, $acct_name, $shares, $price, $amount);
    my $rebal_trans = RebalTran::newSale(
	$reason,
	$ticker->name(),
	$ticker,
	$symbol,
	$acct_name,
	$price,
	$shares,
	$deep_copy);
    $deep_copy->applyTransaction($rebal_trans->transaction());
    push @{$self->{_rebalTrans}}, $rebal_trans;
    return $deep_copy;
}

sub clonePortfolioForTransaction {
    my($self) = @_;

    # The rebalance transaction is relative to the last rebalance
    # transaction/portfolio already stored in self.  So, need to find
    # that last one and make a deep copy of it.
    my $starting_portfolio = $self;
    my $num_rebalance_steps = scalar(@{$self->{_rebalTrans}});
    if ($num_rebalance_steps > 0) {
	$starting_portfolio =
	    $self->{_rebalTrans}->[$num_rebalance_steps-1]->portfolio();
    }
    return $starting_portfolio->newDeepCopy();
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
	$kRebalSymbol,
	$kRebalAccount,
	$kRebalCategory,
	$kRebalAction,
	$kRebalShares,
	$kRebalAmount,
	$kRebalValue,
	$kRebalUnallocated,
	];

    # Need to handle holdings in all portfolios as buys are made.
    # Store all symbols seen across all portfolios as
    # rh_symbols_in_acct->{acct_name}->{symbol}
    my $rh_symbols_in_acct = {};
    foreach my $rebalTran (@{$self->rebalTrans()}) {
	my $portfolio = $rebalTran->portfolio();
	foreach my $acct_name (keys %{$portfolio->accounts()}) {
	    $rh_symbols_in_acct->{$acct_name} = {}
	      unless (defined $rh_symbols_in_acct->{$acct_name});
	    my $acct = $portfolio->account($acct_name);
	    
	    if ( $acct->value() > $gZero ) {
		# For accounts that don't easily support moving money
		# in/out, keep track of the unallocated money
		# separately as well as in $kRebalUnallocated.
		if ( $acct->unallocated() > $gZero ) {
		    # Must match key in printOneLinePortfolioString.
		    my $key = sprintf("_", $acct_name);
		    $rh_symbols_in_acct->{$acct_name}->{$key}++;
		}
		foreach my $symbol (keys %{ $acct->holdings() }) {
		    my $holding = $acct->holding($symbol);
		    if ($holding->value() > $gZero) {
			$rh_symbols_in_acct->{$acct_name}->{$symbol}++;
		    }
		}
	    }
	}
    }

    # Now build the columns headers
    foreach my $acct_name (sort keys %{$rh_symbols_in_acct}) {
	foreach my $symbol (sort keys %{$rh_symbols_in_acct->{$acct_name}}) {
	    my $key = &holdingKey($symbol, $acct_name);
	    push @{$column_headers}, $key;
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
	my $symbol = $transaction->symbol();
	my $key = &holdingKey($symbol,
			      $transaction->account());
	$row->{$kRebalKey} = $key;
	$row->{$kRebalSymbol} = $transaction->symbol();
	$row->{$kRebalAccount} = $transaction->account();
	my $hold_data = $self->{_perHoldingData}->{$key};
	$row->{$kRebalCategory} = 
	    $self->assetAllocation()->symbols()->{$symbol}->name();
	$row->{$kRebalAction} = $transaction->action();
	$row->{$kRebalShares} = $transaction->shares();
	$row->{$kRebalAmount} = $transaction->amount();
    }
    $row->{$kRebalReason} = $reason;
    $row->{$kRebalUnallocated} = $self->unallocated();
    $row->{$kRebalValue} = $self->value();
    foreach my $acct_name (keys %{ $self->accounts() }) {
	my $acct = $self->accounts()->{$acct_name};
	if ( $acct->value() > $gZero ) {
	    my $key = sprintf("_/%s", $acct->name());
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
