package SVK::Command::Copy;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::CommitStatusEditor;
use SVK::Command::Log;
use SVK::Util qw (get_buffer_from_editor);

sub options {
    ($_[0]->SUPER::options,
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return map {$self->arg_depotpath ($_)} @arg;
}

sub run {
    my ($self, $src, $dst) = @_;
    die "different repos?" if $src->{repospath} ne $dst->{repospath};

    $self->{message} = get_buffer_from_editor ('log message', $self->target_prompt,
					       "\n".$self->target_prompt."\n",
					       "/tmp/svk-commitXXXXX")
	unless defined $self->{message};

    $self->{rev} ||= $src->{repos}->fs->youngest_rev;

    SVK::XD::do_copy_direct ( $self->{info},
			      author => $ENV{USER},
			      %$src,
			      dpath => $dst->{path},
			      %$self,
			    );
    return;
}

1;

