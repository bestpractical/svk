package SVK::Depot::Git;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'SVK::Depot';
use constant EMPTY_TREE => '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

sub repos {
    Carp::confess "should not access git depot repos";
}

sub setup {
}

sub run_cmd {
    my $self = shift;
    return `git --git-dir @{[ $self->repospath ]} @_`;
}

1;
