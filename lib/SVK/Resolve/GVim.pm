package SVK::Resolve::GVim;
use strict;
use base 'SVK::Resolve';

sub arguments {
    my $self = shift;
    return (
        qw( -df ),
        @{$self}{qw( merged yours base theirs )}
    );
}

1;
