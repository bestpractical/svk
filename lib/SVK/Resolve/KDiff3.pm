package SVK::Resolve::KDiff3;
use strict;
use base 'SVK::Resolve';

sub arguments {
    my $self = shift;
    return (
        qw( --output ),
        @{$self}{qw( merged base yours theirs )}
    );
}

1;
