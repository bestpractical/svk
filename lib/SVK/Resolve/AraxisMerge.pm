package SVK::Resolve::AraxisMerge;
use strict;
use base 'SVK::Resolve';
use File::Glob;
use SVK::Util qw( catdir );

sub commands { 'compare' }

sub paths {
    return File::Glob::bsd_glob(catdir(
	($ENV{ProgramFiles} || 'C:\Program Files'), 
	'Araxis',
	'Araxis Merge*',
    ));
}

sub arguments {
    my $self = shift;
    return (
	'/wait', '/a3', '/3', 
        qq(/title1:"$self->{label_yours}"),
        qq(/title2:"$self->{label_theirs}"),
        qq(/title3:"$self->{label_base}"),
	@{$self}{qw( yours theirs base merged )},
    );
}

1;
