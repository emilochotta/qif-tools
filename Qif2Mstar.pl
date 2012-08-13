#!/bin/perl

# Re-written version of qif2morningstar.pl

use Portfolio;
use AssetAllocation;
use Account;
use Holding;

use strict;
use warnings;

# --------------------------------------------------------
# Configuration
# --------------------------------------------------------

# Name of the file that contains a summary report generated from
# quicken:
# a.	Select Reports -> Investing -> Portfolio Value
# b.	Resolve any placeholder entries (see link at bottom of report).
# c.	Select Export Data to excel compatible format
# d.	Save as quicken-portfolio.txt
# e.	Open in excel
# f.	Save as quicken-portfolio.csv
my $gSummaryReportFilename = 'quicken/quicken-portfolio.csv';
my $gSummaryName = 'q_summary';

# Name of a director with quicken transaction files (1 or more).  
my $gQifDir = 'quicken';

exit &main();

# --------------------------------------------------------
# Subroutines
# --------------------------------------------------------

sub main {

    print "*************************************************************\n";
    print "Reading portfolio from $gSummaryReportFilename\n";
    my $q_summary_portfolio = Portfolio::newFromQuickenSummaryReport(
	$gSummaryName, $gSummaryReportFilename );

    print "*************************************************************\n";
    print "Reading QIF Account files\n";
    my $rhAccts = Account::newAccountsFromQifDir($gQifDir);
    foreach my $acct (sort keys %{$rhAccts}) {
	print "Account ", $acct, "\n";
	my @lines;
	$rhAccts->{$acct}->printToStringArray(\@lines,
					      '',   # Prefix
					      0);   # Print Transactions
	print join("\n", @lines), "\n";
    }
    my $rhPortfolios = Portfolio::newPortfoliosFromAccounts(
	$rhAccts, \%Portfolio::PortfolioDefs);

    # Compares portfolio file with data read from qif files as a
    # sanity check.
    my @lines;
    $q_summary_portfolio->Compare($rhPortfolios->{'all'}, \@lines);
    print join("\n", @lines), "\n";

    #
    # TODO: Transport CombineTransactions from the old version
    # so that there aren't multiple events on the same day.
    #
    # TODO: Generate multiple spreadsheets per portfolio based
    # on asset classes within the portfolio.
    foreach my $p_name (sort keys %{$rhPortfolios}) {
	next if $p_name eq $gSummaryName;
	
	my $portfolio = $rhPortfolios->{$p_name};
	my $fname = sprintf("out/%s.csv", $portfolio->name());
	$portfolio->printToMstarCsvFile($fname);

	# Only the summary portfolio will have usable prices.
	$portfolio->copyPrices($q_summary_portfolio);
    }

    # 
    # TODO: Bring in portfolio definitions and add support for
    # rebalancing portfolios.
    &Read_Asset_Allocation_Csv_Per_Portfolio( $rhPortfolios );
    foreach my $portfolioName ( keys %{ $rhPortfolios } ) {
	$rhPortfolios->{$portfolioName}->printRebalanceCsvFile('out');
    }

    return 0;
}

sub Read_Asset_Allocation_Csv_Per_Portfolio {
    my ($rhPortfolios) = @_;

    foreach my $portfolioName ( keys %{ $rhPortfolios } ) {
	my $portfolio = $rhPortfolios->{$portfolioName};
	$portfolio->SetAssetAllocation(
	    AssetAllocation::NewFromCsv($portfolioName));
    }
}


    


