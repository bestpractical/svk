package SVN::StatusEditor;;
use strict;
our $VERSION = '0.05';
our @ISA = qw(SVN::Delta::Editor);

sub set_target_revision {
    my ($self, $revision) = @_;
}

sub open_root {
    my ($self, $baserev) = @_;
    return '';
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    $path = "$self->{copath}/$path";
    $self->{info}{$path}{status} = ['A'];
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    $path = "$self->{copath}/$path";
    return $path;
}

sub apply_textdelta {
    my ($self, $path) = @_;
    $self->{info}{$path}{status}[0] ||= 'M';
    return undef;
}

sub close_file {
    my ($self, $path) = @_;
    print sprintf ("%1s%1s \%s\n", $self->{info}{$path}{status}[0],
		   $self->{info}{$path}{status}[1] || '',
		   $path);
}

1;
