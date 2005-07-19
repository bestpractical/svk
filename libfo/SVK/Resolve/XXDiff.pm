package SVK::Resolve::XXDiff;
use strict;
use base 'SVK::Resolve';

sub arguments {
    my $self = shift;
    return (
        qw( -m -O -M ),
        @{$self}{qw( merged yours base theirs )}
    );
}

1;
