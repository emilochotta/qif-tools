package AssetAllocation;
use AssetCategory;
use Ticker;
use Text::CSV_XS;
use strict;

#-----------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------

my $gDebug = 1;

# Used as a prefix on filenames.  
my $gAssetAllocationPrefix = 'asset-allocation-';

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,       # Must be defined.
	_categories => shift, # Hash of AssetCategory by category name.
	_symbols => shift,    # Hash by AssetCategory ticker symbol.
    };
    !defined($self->{_categories}) && ($self->{_categories} = {});
    !defined($self->{_symbols}) && ($self->{_symbols} = {});
    bless $self, $class;
    return $self;
}

sub name { $_[0]->{_name}; }
sub categories { $_[0]->{_categories}; }
sub category { $_[0]->{_categories}->{$_[1]}; }
sub symbols { $_[0]->{_symbols}; }
sub symbol { $_[0]->{_symbol}->{$_[1]}; }

sub NewFromCsv {
    my ($name) = @_;

    my $fname = $gAssetAllocationPrefix . $name . ".csv";

    $gDebug && print "Try to read $fname\n";
    my $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ });
    if ( open my $io, "<", $fname ) {
	my $aa = AssetAllocation->new($name);
	
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
 	    $gDebug && printf( "Category \"%s\" is %f percent:\n",
			       $category, $allocation);
	    # comma separated list
	    my $raTickerSymbols = [ split(/,/, $row->[9]) ];  

	    # Share a single object.  These are essentially read-only.
	    my $assetCategory = AssetCategory->new(
		$category,
		$allocation,
		$raTickerSymbols,
		);

 	    foreach my $symbol (@{ $raTickerSymbols }) {
		# Make sure we actually have Ticker info for each symbol.
 		my $ticker = Ticker::getBySymbol($symbol);

		$aa->{_symbols}->{$symbol} = $assetCategory;
		$gDebug && printf( "Symbol \"%s\" is \"%s\" %.2f\n",
				   $symbol, $category, $allocation);
	    }
	    
	    $aa->{_categories}->{$category} = $assetCategory;
 	}
	close $io;
	return $aa;
    } else {
	print "Skipping $fname: $!\n";
	return;
    }
}


1;
