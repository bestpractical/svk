package SVK::DeleteEditor;
use strict;
use SVK::StatusEditor;
our $VERSION = '0.05';
our @ISA = qw(SVK::StatusEditor);
use SVK::I18N;

sub close_file {
    my ($self, $path) = @_;

    if ($self->{info}{$path}{status}[0] eq 'M') {
	die loc("%1 changed", $self->{info}{$path}{dpath});
    }
    else {
	die loc("%1 is scheduled, use 'svk revert'", $self->{info}{$path}{dpath});
    }
}

sub close_directory {
    my ($self, $path) = @_;
    die loc("%1 is scheduled, use 'svk revert'", $self->{info}{$path}{dpath})
	if $self->{info}{$path}{status}[0] eq 'A';
}

sub delete_entry {
    my ($self, $path) = @_;
    &{$self->{cb_delete}} ("$self->{dpath}/$path", "$self->{copath}/$path");
}

1;
