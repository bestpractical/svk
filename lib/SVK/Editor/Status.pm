package SVK::Editor::Status;
use strict;
require SVN::Delta;
our $VERSION = '0.05';
our @ISA = qw(SVN::Delta::Editor);

sub open_root {
    my ($self, $baserev) = @_;
    $self->{info}{$self->{copath}}{status} = ['', '', ''];
    return $self->{copath};
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    my $opath = $path;
    $path = "$self->{copath}/$opath";
    $self->{info}{$path}{dpath} = "$self->{dpath}/$opath";
    $self->{info}{$path}{status} = [$self->{conflict}{$path} || 'A', '', $arg[0] ? '+' : ''];
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    my $opath = $path;
    $path = "$self->{copath}/$opath";
    $self->{info}{$path}{dpath} = "$self->{dpath}/$opath";
    $self->{info}{$path}{status} = [$self->{conflict}{$path} || '', '', ''];
    return $path;
}

sub apply_textdelta {
    my ($self, $path) = @_;
    $self->{info}{$path}{status}[0] = 'M'
	if !$self->{info}{$path}{status}[0] || $self->{info}{$path}{status}[2];
    return undef;
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    my $stat = $self->{info}{$path}{status};
    $stat->[1] = 'M' unless $stat->[0] eq 'A';
}

sub close_file {
    my ($self, $path) = @_;
    my $rpath = $path;
    $rpath =~ s|^\Q$self->{copath}\E/|$self->{rpath}|;
    print sprintf ("%1s%1s%1s \%s\n", @{$self->{info}{$path}{status}},
		   $rpath);
    delete $self->{conflict}{$path};
}

sub absent_file {
    my ($self, $path) = @_;
    print "!   $self->{rpath}$path\n";
}

sub delete_entry {
    my ($self, $path) = @_;
    print "D   $self->{rpath}$path\n";
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    my $opath = $path;
    $path = "$self->{copath}/$opath";
    my $rpath = $opath;
    $rpath = "$self->{rpath}$opath" if $self->{rpath};
    $self->{info}{$path}{dpath} = "$self->{dpath}/$opath";
    $self->{info}{$path}{status} = ['A', '', $arg[0] ? '+' : ''];
    print sprintf ("%1s%1s%1s \%s\n", @{$self->{info}{$path}{status}}, $rpath);
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    my $opath = $path;
    $path = "$self->{copath}/$opath";
    $self->{info}{$path}{dpath} = "$self->{dpath}/$opath";
    $self->{info}{$path}{status} = ['', '', ''];
    return $path;
}

sub change_dir_prop {
    my ($self, $path, $name, $value) = @_;
    my $stat = $self->{info}{$path}{status};
    $stat->[1] = 'M' unless $stat->[0] eq 'A';
}

sub close_directory {
    my ($self, $path) = @_;
    my $rpath = $path;
    $rpath =~ s|^\Q$self->{copath}\E/|$self->{rpath}|;
    if ($rpath eq $self->{copath}) {
	$rpath = $self->{rpath};
	chop $rpath;
    }
    for (grep {"$path/" eq substr ($_, 0, length($path)+1)}
	 sort keys %{$self->{conflict}}) {
	delete $self->{conflict}{$_};
	s|^\Q$self->{copath}\E/|$self->{rpath}|;

	print sprintf ("%1s%1s  \%s\n", 'C', '', $_);
    }
    my $stat = $self->{info}{$path}{status};
    print sprintf ("%1s%1s%1s \%s\n", @$stat, $rpath || '.')
	if ($stat->[0] || $stat->[1]) && $stat->[0] ne 'A';
}

sub absent_directory {
    my ($self, $path) = @_;
    print "!   $self->{rpath}$path\n";
}

sub conflict {
    my ($self, $path) = @_;
    my $opath = $path;
    $path = "$self->{copath}/$opath";
    $self->{conflict}{$path} = 'C';
}

1;
