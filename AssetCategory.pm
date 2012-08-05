package AssetCategory;
use Ticker;
use strict;

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,     # string name of the category.
	_value => shift,    # number, percent allocation.
	_tickers => shift,  # tickers, ordered from best to worst.
    };
    bless $self, $class;
    return $self;
}
1;
