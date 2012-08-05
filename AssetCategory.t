#!/bin/perl

#
# Test the functionality of AssetCategory.pm
#
use AssetCategory;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# Test basic object creation
sub test_new : Test(2) {
    my $a = new AssetCategory();
    ok(defined($a), 'AssetCategory object was created');
    ok($a->isa('AssetCategory'),
       'AssetCategory object isa AssetCategory');
};

Test::Class->runtests;
