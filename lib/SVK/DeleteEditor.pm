package SVK::DeleteEditor;
use strict;
use SVK::StatusEditor;
our $VERSION = '0.05';
our @ISA = qw(SVK::StatusEditor);

sub close_file {
    my ($self, $path) = @_;

    if ($self->{info}{$path}{status}[0] eq 'M') {
	die "$self->{info}{$path}{dpath} changed";
    }
    else {
	die "$self->{info}{$path}{dpath} is scheduled, use svk revert";
    }
}

sub close_directory {
    my ($self, $path) = @_;
    die "$self->{info}{$path}{dpath} is scheduled, use svk revert"
	if $self->{info}{$path}{status}[0] eq 'A';
}

sub delete_entry {
    my ($self, $path) = @_;
    &{$self->{cb_delete}} ("$self->{dpath}/$path", "$self->{copath}/$path");
}

1;
