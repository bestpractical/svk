package SVK::Resolve::FileMerge;
use strict;
use base 'SVK::Resolve';

sub commands { 'FileMerge' }

sub paths {
    '/Developer/Applications/Utilities/FileMerge.app/Contents/MacOS',
    '/Developer/Applications/FileMerge.app/Contents/MacOS',
}

sub arguments {
    my $self = shift;
    return (
        -left       => $self->{yours},
        -right      => $self->{theirs},
        -ancestor   => $self->{base},
        -merge      => $self->{merged}
    );
}

1;
