package SVK::Command::Import;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::CommitStatusEditor;
use SVK::Util qw (get_buffer_from_editor);

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    $arg[1] = '' if $#arg < 1;

    return ($self->arg_depotpath ($arg[0]), $self->arg_path ($arg[1]));
}

sub run {
    my ($self, $target, $source) = @_;

    unless (defined $self->{message} || $self->{check_only}) {
	$self->{message} = get_buffer_from_editor
	    ('log message', $self->target_prompt,
	     "\n".$self->target_prompt."\n", "svk-commitXXXXX");
    }

    SVK::XD::do_import ( $self->{info},
			 %$self,
			 %$target,
			 copath => $source,
		       );
    return;
}

1;
