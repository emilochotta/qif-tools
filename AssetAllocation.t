#!/bin/perl

#
# Test the functionality of AssetAllocation.pm
#
use AssetAllocation;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# Test basic object creation
sub test_new : Test(2) {
    my $a = new AssetAllocation();
    ok(defined($a), 'AssetAllocation object was created');
    ok($a->isa('AssetAllocation'), 'AssetAllocation object isa AssetAllocation');
};

Test::Class->runtests;
