package SVK::Resolve::AraxisMerge;
use strict;
use base 'SVK::Resolve';
use SVK::Util qw( catdir bsd_glob );

sub commands { 'consolecompare' }

sub paths {
    my $araxis_dir = catdir(
	($ENV{ProgramFiles} || 'C:\Program Files'), 
	'Araxis',
    );

    return(
        $araxis_dir,
        bsd_glob(
            catdir($araxis_dir, 'Araxis Merge*')
        ),
    );
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
