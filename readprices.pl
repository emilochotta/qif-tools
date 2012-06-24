#!/bin/perl

package Qif2Morningstar;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw();

use strict;

&Read_QIF_Prices('quicken/etrade-5557.QIF');

sub Read_QIF_Prices() {
    my $filename = shift;

    open(my $fh, "<", $filename) or die "cannot open $filename: $!";

    while ( <$fh> ) {
#	print $_;
	if ( /^!Type:Prices$/ ) {
	    my $next_line = <$fh>;
	    if ( defined $next_line ) {
		$next_line =~ tr/\"\r\n//d;
		my ($ticker, $price, $date) = split(/,/, $next_line);
		$date = &Convert_Qif_Date($date);
		print "\"", join( "\", \"", $ticker, $date, $price), "\"\n";
	    }
	}
    }
}
    
sub Convert_Qif_Date {
    my $date = shift;
    $date =~ s/\s*(\d+)\/\s*(\d+)'1(\d)/$1-$2-201$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)' (\d)/$1-$2-200$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)\/(\d+)/$1-$2-19$3/;
    return $date;
}


