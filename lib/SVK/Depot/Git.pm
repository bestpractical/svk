package SVK::Depot::Git;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'SVK::Depot';

sub repos {
    Carp::confess "should not access git depot repos";
}

1;
