package SVK::Resolve::P4WinMerge;
use strict;
use base 'SVK::Resolve';
use File::Copy ();

sub paths { 'C:\Program Files\Perforce' }

sub commands { 'p4winmrg' }

sub arguments {
    my $self = shift;
    return (-nsf => @{$self}{qw( base theirs yours merged )});
}

1;
