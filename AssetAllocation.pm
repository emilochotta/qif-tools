package AssetAllocation;
use AssetCategory;
use Text::CSV_XS;
use strict;

sub new
{
    my $class = shift;
    my $self = []; # List of AssetCategory
    bless $self, $class;
    return $self;
}

sub Read_From_Csv {
    my ($self, $fname, $rhTickers) = @_;
	
#    print "Try to read $fname\n";
    my $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ });
    if ( open my $io, "<", $fname ) {
	# Make sure file matches expected column headers
	my $header = $csv->getline ($io);
	if ( $header->[0] ne "Level 1"
	     || $header->[1] ne "L1 Allocation"
	     || $header->[2] ne "Level 2"
	     || $header->[3] ne "L2 Allocation"
	     || $header->[4] ne "Level 3"
	     || $header->[5] ne "L3 Allocation"
	     || $header->[6] ne "Level 4"
	     || $header->[7] ne "L4 Allocation"
	     || $header->[8] ne "Final Allocation"
	     || $header->[9] ne "Ticker"
	    ) {
	    print "Header incorrect in $fname\n";
	    return;
	}

	# handle the asset allocation categories
	while (my $row = $csv->getline ($io)) {
#	    print "\"", join(", ", @{ $row }), "\"\n";
	    my $category = $row->[0];
	    next if $category eq "";
	    for my $i (2, 4, 6) {
		my $text = $row->[$i];
		$category .= "-" . $text unless $text eq "";
	    }
	    my $allocation = $row->[8];
	    $allocation =~ tr/%//d;
# 	    printf( "Category \"%s\" is %f percent:\n",
# 		    $category, $allocation);
	    my $raTickers = [ split(/,/, $row->[9]) ];  # comma separated list
# 	    $rhAssetAllocations->{$portfolio}->{'tickers'}->{$category} = $raTickers;
# 	    foreach my $ticker ( @{ $raTickers } ) {
# 		$rhAssetAllocations->{$portfolio}->{'categories'}->{$ticker} = $category;
# #		printf( "Ticker \"%s\" is \"%s\" %.2f\n", $ticker, $category, $allocation);
# 	    }
 	}
	close $io;
    } else {
	print "Skipping $fname: $!\n";
	return;
    }
}


1;
