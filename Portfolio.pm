package Portfolio;
use strict;

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,
	_assetAllocation => shift,
    };
    bless $self, $class;
    return $self;
}

sub Set_Asset_Allocation {
    my ($self, $a) = @_;
    $self->{_assetAllocation} = $a if defined $a;
    return $self->{_assetAllocation};
}

1;
