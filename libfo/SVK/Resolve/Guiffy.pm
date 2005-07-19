package SVK::Resolve::Guiffy;
use strict;
use base 'SVK::Resolve';
use SVK::Util qw( catdir bsd_glob );

sub paths {
    return bsd_glob(catdir(
	($ENV{ProgramFiles} || 'C:\Program Files'), 
	'Guiffy*',
    ));
}

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
