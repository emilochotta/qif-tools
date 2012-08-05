#!/bin/perl

# A portfolio is a collection of holdings or accounts.

package Portfolio;

use Account;
use AssetAllocation;
use Holding;
use Ticker;
use Transaction;
use Transactions;
use Text::CSV_XS;
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
	_assetAllocation => shift,
	_holdings => shift,         # Hash by symbol.
	_accounts => shift,         # Hash by acct name.
    };
    if (defined($PortfoliosByName->{$self->{_name}})) {
	die "A portfolio named $self->{_name} already exists.\n";
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
	    
	    $gDebug && printf( "Found %f shares of \"%s\" at %.2f\n",
			       $shares, $name, $price );
	}
    }
    close $io;
    return $portfolio;
}
    
sub Set_Asset_Allocation {
    my ($self, $a) = @_;
    $self->{_assetAllocation} = $a if defined $a;
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
		if (defined($p->{_holdings}) &&
		    defined($p->{_holdings}->{$symbol})) {

		    # Holding with this symbol already exists, so
		    # we append the transactions from this account
		    # to the transactions for that other account.
		    my $holding = $p->holding($symbol);
		    $holding->appendHoldingTransactions(
			$account->holding($symbol));
		} else {
		    $p->{_holdings}->{$symbol} =
			$account->holdings()->{$symbol};
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
	push @my_symbols, $symbol;
	if (length $symbol > $width) {
	    $width = length $symbol;
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

1;
