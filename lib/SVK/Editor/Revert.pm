package SVK::Editor::Revert;
use strict;
use SVK::Editor::Status;
our $VERSION = '0.05';
our @ISA = qw(SVK::Editor::Status);

sub close_file {
    my ($self, $path) = @_;

    if ($self->{info}{$path}{status}[0] eq 'M') {
	$self->{cb_revert}->($self->{info}{$path}{dpath}, $path);
    }
    else {
	$self->{cb_unschedule}->($self->{info}{$path}{dpath}, $path);
    }
}

sub absent_file {
    my ($self, $path) = @_;
    $self->{cb_revert}->("$self->{dpath}/$path", "$self->{copath}/$path");
}

sub close_directory {
    my ($self, $path) = @_;
    $self->{cb_unschedule}->($self->{info}{$path}{dpath}, $path)
	    if $self->{info}{$path}{status}[0] eq 'A' ||
		$self->{info}{$path}{status}[1] eq 'M';
}

sub absent_directory {
    my ($self, $path) = @_;
    $self->{cb_revert}->("$self->{dpath}/$path", "$self->{copath}/$path");
}

sub delete_entry {
    my ($self, $path) = @_;
    $self->{cb_revert}->("$self->{dpath}/$path", "$self->{copath}/$path");
}

1;
