package Holding;
use strict;

sub new
{
    my $class = shift;
    my $self = {
	_ticker => shift,        # Ref to Ticker object.
	_inAccount => shift,     # Ref to Account object.
	     # Ref to array of Transaction objects (maybe undef)
        _transactions => shift,  
	_shares => shift,        # Current shares
	_price => shift,         # Current price
    };
    bless $self, $class;
    return $self;
}
1;
