package AssetCategory;
use Ticker;
use strict;

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,     # string name of the category.
	_value => shift,    # number, percent allocation.
	_symbols => shift,  # Ref to Array of ticker symbols
    };
    bless $self, $class;
    return $self;
}

sub name { $_[0]->{_name}; }
sub value { $_[0]->{_value}; }
sub symbols { $_[0]->{_symbols}; }

1;
