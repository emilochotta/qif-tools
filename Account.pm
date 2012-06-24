package Account;
use Holding;
use strict;

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,
	_taxable => shift,
        _cash => shift,
        _holdings  => shift,
	_inPortfolios => shift,
    };
    bless $self, $class;
    return $self;
}
1;
