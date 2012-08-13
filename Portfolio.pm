#!/bin/perl

# A portfolio is a collection of holdings or accounts.

package Portfolio;

use Account;
use AssetAllocation;
use AssetCategory;
use Holding;
use Ticker qw($kCash);
use Transaction;
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
    );

# Use a bit vec for Analysis of holdings w.r.t. asset allocation.
our $IDEAL = 1;              # Practically perfect in every way.
our $OVER_ALLOCATION = 2;    # Too much of this holding.
our $HIGH_DIVIDEND_TAX = 4;  # High yield in a taxable account.
our $CAPITAL_LOSS = 8;       # Currently have a capital loss.
our $NON_IDEAL_TICKER = 16;  # Not the first ticker on the list.

# Portfolio analysis hash names / CSV column header names.
my $kCategory = 'Category';
my $kAllocTickers = 'Alloc Tickers';
my $kOwnedTickers = 'Owned Tickers';
my $kValue = 'Value';
my $kAllocation = 'Allocation';
my $kCurrentWeight = 'Current Weight';
my $kDifference = 'Difference';
my $kDiffPercent = 'Diff %';
my $kTargetValue = 'Target Value';
my $kTargetValueDiff = 'Target Value Diff';
my $kRebalance = 'Rebalance';
my $kTargetBuy = 'Target Buy';
my $kBuy = 'Buy';

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
	_name => shift,             # Must be defined.

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

	# Hash by symbol.  Analysis of portfolio against asset
	# allocation.
	_perHoldingData => shift,

	# Total portfolio value.  Calculated from holdings (not
	# accounts.)
	_value => shift,
    };
    if (defined($PortfoliosByName->{$self->{_name}})) {
	die "A portfolio named $self->{_name} already exists.\n";
    }
    if (!defined($self->{_perCatData})) {
	$self->{_perCatData} = {};
    }
    
    bless $self, $class;
    $PortfoliosByName->{$self->{_name}} = $self;
    return $self;
}

sub name { $_[0]->{_name}; }
sub assetAllocation { $_[0]->{_assetAllocation}; }
sub holdings { $_[0]->{_holdings}; }
sub holding { $_[0]->{_holdings}->{$_[1]}; }
sub accounts { $_[0]->{_accounts}; }
sub perCatData { $_[0]->{_perCatData}; }
sub perHoldingData { $_[0]->{_perHoldingData}; }
sub value { $_[0]->{_value}; }

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
	    
	    $gDebug && printf("Found %f shares of \"%s\" at %.2f\n",
			      $holding->shares(), $name,
			      $holding->price());
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
    print "  Writing $fname\n";
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
    # 2) Compute portfolio of ideal holdings according to asset
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
    #   - Certain accounts have limit symbols they can hold, e.g.
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

    my $availableTaxAdvantagedValue =
	$self->computeTaxAdvantagedValue();

    printf("Tax Advantaged total is %f\n", $availableTaxAdvantagedValue);
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

	next if $alloc_value == 0;

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
	$gDebug && printf("Category %s = %f, total %f\n",
			  $cat_name, $category_value,
			  $total_portfolio_value);
	my $alloc_symbols = join(",", @alloc_symbols);
	my $owned_symbols = join(",", @owned_symbols);

	$self->{_perCatData}->{$cat_name} = {};
	my $cat_data = $self->{_perCatData}->{$cat_name};
	$cat_data->{$kCategory} = $cat_name;
	$cat_data->{$kAllocTickers} = $alloc_symbols;
	$cat_data->{$kOwnedTickers} = $owned_symbols;
	$cat_data->{$kValue} = $category_value;
	$cat_data->{$kAllocation} = $alloc_value;

	my $current_weight = $category_value / $self->value();
	$cat_data->{$kCurrentWeight} = $current_weight;
	
	my $difference =
	    $cat_data->{$kAllocation} - $current_weight;
	$cat_data->{$kDifference} = $difference;

	my $diff_percent = 0;
	if ( $cat_data->{$kAllocation} != 0 ) {
	    $diff_percent =
		$difference / $cat_data->{$kAllocation};
	}
	$cat_data->{$kDiffPercent} = $diff_percent;

	my $target_value = $self->value() * $cat_data->{$kAllocation};
	$cat_data->{$kTargetValue} = $target_value;

	my $target_value_diff = $target_value - $category_value;
	$cat_data->{$kTargetValueDiff} = $target_value_diff;

	my $rebalance = 0;
	my $target_buy = 0;

	# Rebalance rule: more than 5% delta and > $5000 difference.
	if ( abs($diff_percent) > 0.05 && abs($target_value_diff) > 5000 ) {
	    $rebalance = 1;
	    $target_buy = $target_value_diff;
	    $excess_buy += $target_buy;
	}	    
	$cat_data->{$kRebalance} = $rebalance;
	$cat_data->{$kTargetBuy} = $target_buy;
    }

    if ( $total_alloc ne 1.0 ) {
	printf("Warning: Total Asset Allocation isn't 1, it's %f, (diff %f)\n",
	    $total_alloc, 1.0 - $total_alloc);
    }
    if (abs($total_portfolio_value-$self->value()) > $gZero) {
	printf("Warning: Total Portfolio Value by asset claass (%f) != value by holding (%f)\n",
	    $total_portfolio_value, $self->value());
    }
}

sub printCategoryLinesString {
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $csv,           # In: A CSV object if you want to reuse one.
	) = @_;

    my $column_headers = [$kCategory, $kAllocTickers, $kOwnedTickers, $kValue,
			  $kAllocation, $kCurrentWeight, $kDifference,
			  $kDiffPercent, $kTargetValue, $kTargetValueDiff,
			  $kRebalance, $kTargetBuy, $kBuy];
    &Util::printCsv($column_headers, $csv, $raS);

    # Now write it out
    foreach my $cat_name (sort
			  { $self->{_perCatData}->{$b}->{$kTargetValueDiff}
			    <=> $self->{_perCatData}->{$a}->{$kTargetValueDiff} }
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
    $totals->{$kValue} = $self->value();
    # $totals->{$kBuy} = $excess_buy;
    &Util::printHashToCsv($totals, $column_headers,
			  undef, $csv, $raS);
}

sub printTickerLinesString {
    my($self, 
       $raS,           # Out: Output is written back to this array. 
       $csv,           # In: A CSV object if you want to reuse one.
	) = @_;

    my $ticker_headers = ["Name", "Ticker", "Account", "Price", "Shares",
	"Value", "Tax Advantaged"];
    &Util::printCsv($ticker_headers, $csv, $raS);
    
    foreach my $acct_name (sort keys %{ $self->accounts() }) {
	my $acct = $self->accounts()->{$acct_name};
	foreach my $holding_name (sort keys %{ $acct->holdings() }) {
	    my $holding = $acct->holdings()->{$holding_name};
	    my $ticker = $holding->ticker();
	    next if ($ticker->skip());
	    my $name = $ticker->name();
	    my $symbol = $ticker->symbol();
	    my $price = $holding->price();
	    my $shares = $holding->shares();
	    my $value = $holding->value();
	    my $tax_advantaged = ($acct->tax_advantaged()) ? $value : 0;
	    if ( $shares > $gZero ) {
		# TODO: list asset category and any problems
		# with the holding (non-ideal ticker, yield too
		# high for taxable account, etc.)
		my $line = [$name, $symbol, $acct_name, $price, $shares,
		    $value, $tax_advantaged];
		&Util::printCsv($line, $csv, $raS);
		if (!defined $self->assetAllocation()->symbols()->{$symbol} ) {
		    print "WARNING: No asset allocation class for ticker \"$symbol\"\n";
		    printf("Add that ticker to asset-allocation-%s.csv\n",
			   $self->name());
		}
	    }
	}
    }
}

sub computeTaxAdvantagedValue
{
    my($self) = @_;
    my $value = 0;
    foreach my $a (keys %{$self->accounts()}) {
	my $account = $self->accounts()->{$a};
	if ($account->tax_advantaged()) {
	    $value += $account->value();
	}
    }
    return $value;
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
