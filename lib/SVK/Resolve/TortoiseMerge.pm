package SVK::Resolve::TortoiseMerge;
use strict;
use base 'SVK::Resolve';
use SVK::Util qw( catdir );

sub paths {
    return catdir(
	($ENV{ProgramFiles} || 'C:\Program Files'), 
	'TortoiseSVN',
	'bin',
    );
}

sub arguments {
    my $self = shift;
    return (
        "/yours:$self->{yours}",
        "/base:$self->{base}",
        "/theirs:$self->{theirs}",
        "/yourname:$self->{label_yours}",
        "/basename:$self->{label_base}",
        "/theirname:$self->{label_theirs}",
        "/merged:$self->{merged}",
    );
}

1;
