package SVK::CommitStatusEditor;
use strict;
require SVK::StatusEditor;
our $VERSION = '0.05';
our @ISA = qw(SVK::StatusEditor);

sub close_file {
    my ($self, $path) = @_;
    my $info = $self->{info}{$path}{status};
    push @{$self->{targets}}, [$info->[0] || ($info->[1] ? 'P' : ''),
			       $path];
    print {$self->{fh}} sprintf ("%1s%1s \%s\n", $info->[0], $info->[1],
				 $path) if $self->{fh};


}

sub delete_entry {
    my ($self, $path) = @_;
    push @{$self->{targets}}, ['D', "$self->{copath}/$path"];
    print {$self->{fh}} "D  $self->{copath}/$path\n" if $self->{fh};

}

sub close_directory {
    my ($self, $path) = @_;
    my $info = $self->{info}{$path}{status};
    return unless $info->[0] || $info->[1];
    push @{$self->{targets}}, [$info->[1] ? 'P' : $info->[0],
			       $path];
    print {$self->{fh}} sprintf ("%1s%1s \%s\n", $info->[0], $info->[1],
				 $path) if $self->{fh};

}

1;
