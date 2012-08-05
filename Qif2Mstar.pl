#!/bin/perl

# Re-written version of qif2morningstar.pl

use Portfolio;
use Account;
use Holding;

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
my $gSummaryReportFilename = 'quicken-portfolio.csv';

# Name of a director with quicken transaction files (1 or more).  
my $gQifDir = 'quicken';

exit &main();

# --------------------------------------------------------
# Subroutines
# --------------------------------------------------------

sub main {

    print "*************************************************************\n";
    print "Reading portfolio from $quickenPortfolio\n";
    my $q_summary_portfolio = Portfolio::newFromQuickenSummaryReport(
	'q_summary', $gSummaryReportFilename );

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

#     $rh_portfolio_definitions =
# 	&ReadPortfolioDefinitions($portfolio_definition_file);
#     foreach $p ( keys $rh_porfolio_definitions ) {
# 	$rh_portfolios->{$p} = Portfolio::new();
#     }
    return 0;
}

    


