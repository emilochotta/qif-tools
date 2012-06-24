#!/bin/perl

# Re-written version of qif2morningstar.pl

# --------------------------------------------------------
# Subroutines
# --------------------------------------------------------

sub main {

    print "*************************************************************\n";
    print "Reading portfolio from $quickenPortfolio\n";
    my $q_summary_portfolio = Porfolio::new();
    $q_summary_portfolio->ReadFromQuickenSummaryReport($q_portfolio_file);

    print "*************************************************************\n";
    print "Reading transactions from QIF files\n";
    &ReadQifFilesToAccounts( $rhQif, $qifDir );

    $rh_portfolio_definitions =
	&ReadPortfolioDefinitions($portfolio_definition_file);
    foreach $p ( keys $rh_porfolio_definitions ) {
	$rh_portfolios->{$p} = Portfolio::new();
    }
}
