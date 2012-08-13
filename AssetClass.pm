#!/bin/perl

# An asset class is a simple approximation of morningstar asset
# classes.  These are used to slice portfolios, making it easier to
# analyze U.S. vs International, etc.  A particular asset can be in
# multiple asset classes.  An AssetCategory is a similar concept, but
# is part of an asset allocation and an asset can be in only one
# AssetCategory.  (TODO): I'm not sure if it makes sense to try to
# unify these is some way.

package AssetClass;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw($US_STOCK $INTL_STOCK $BOND $REAL_ASSET $CASH);

# Use a bit vec for Morningstar asset classes.
# Something has to have >25% to be in the category
our $US_STOCK = 1;
our $INTL_STOCK = 2;
our $BOND = 4;
our $REAL_ASSET = 8;
our $CASH = 16;
