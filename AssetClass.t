#!/bin/perl

#
# Test the functionality of AssetClass.pm
#
use AssetClass;
use base qw(Test::Class);
use Test::More;
use strict;
use warnings;

# Test basic object creation
sub test_new : Test(2) {
    ok($AssetClass::US_STOCK != $AssetClass::INTL_STOCK,
       'Classes use different ids');
    ok($AssetClass::BOND != $AssetClass::INTL_STOCK,
       'Classes use different ids');
};

Test::Class->runtests;
