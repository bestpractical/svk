package SVK::Depot::Git;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'SVK::Depot';

sub repos {
    Carp::confess "should not access git depot repos";
}

sub run_cmd {
    my $self = shift;
    return `git --git-dir @{[ $self->repospath ]} @_`;
}

1;
