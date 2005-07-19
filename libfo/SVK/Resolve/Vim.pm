package SVK::Resolve::Vim;
use strict;
use base 'SVK::Resolve';

sub arguments {
    my $self = shift;
    return (
        qw( -d ),
        @{$self}{qw( merged yours base theirs )}
    );
}

1;
