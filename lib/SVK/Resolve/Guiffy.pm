package SVK::Resolve::Guiffy;
use strict;
use base 'SVK::Resolve';

sub paths { 'C:\Program Files\Guiffy62' }

sub arguments {
    my $self = shift;
    return (
        '-s',
        "-h1=$self->{label_yours}",
        "-h2=$self->{label_theirs}",
        '-hm=Merged',
        @{$self}{qw( yours theirs base merged )}
    );
}

1;
