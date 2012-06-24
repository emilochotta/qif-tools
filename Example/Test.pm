package Example::Test;
use base qw(Test::Class);
use Test::More;

# setup methods are run before every test method. 
sub make_fixture : Test(setup) {
    my $array = [1, 2];
    shift->{test_array} = $array;
};

# a test method that runs 1 test
sub test_push : Test {
    my $array = shift->{test_array};
    push @$array, 3;
    is_deeply($array, [1, 2, 3], 'push worked');
};

# a test method that runs 4 tests
sub test_pop : Test(4) {
    my $array = shift->{test_array};
    is(pop @$array, 2, 'pop = 2');
    is(pop @$array, 1, 'pop = 1');
    is_deeply($array, [], 'array empty');
    is(pop @$array, undef, 'pop = undef');
};

# teardown methods are run after every test method.
sub teardown : Test(teardown) {
    my $array = shift->{test_array};
    diag("array = (@$array) after test(s)");
};
1;
