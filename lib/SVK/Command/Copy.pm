package SVK::Command::Copy;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Commit );
use SVK::Util qw( get_anchor );
use SVK::I18N;

sub options {
    ($_[0]->SUPER::options,
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    $self->usage if $#arg < 0 || $#arg > 1;
    return ($self->arg_depotpath ($arg[0]), $self->arg_co_maybe ($arg[1] || ''));
}

sub lock {
    my $self = shift;
    $_[1]->{copath} ? $self->lock_target ($_[1]) : $self->lock_none;
}

sub do_copy_direct {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $edit = $self->get_commit_editor ($fs->revision_root ($fs->youngest_rev),
					 sub { print loc("Committed revision %1.\n", $_[0]) },
					 '/', %arg);
    # XXX: check parent, check isfile, check everything...
    $edit->open_root();
    $edit->copy_directory ($arg{dpath}, "file://$arg{repospath}$arg{path}",
			   $arg{rev});
    $edit->close_edit();
}

sub run {
    my ($self, $src, $dst) = @_;
    die loc("repos paths mismatch") if $src->{repospath} ne $dst->{repospath};
    $self->{rev} ||= $src->{repos}->fs->youngest_rev;
    my $fs = $src->{repos}->fs;
    if ($dst->{copath}) {
	my $xdroot = $self->{xd}->xdroot (%$dst);
	# XXX: prevent recursion, etc
	if (-d $dst->{copath}) {
	    my ($name) = $src->{depotpath} =~ m|(/[^/]+)/?$|;
#	    $dst = $self->arg_copath ("$dst->{depotpath}$name");
	    $dst->{depotpath} .= $name;
	    $dst->{path} .= $name;
	    $dst->{copath} .= $name;
	}
	my ($anchor, $target, $sanchor, $starget) = get_anchor (1, $dst->{path}, $src->{path});

	my $editor = $self->{xd}->get_editor ( %$dst,
					       report => $dst->{report},
					       oldroot => $xdroot,
					       newroot => $xdroot,
					       anchor => $sanchor,
					       target => $starget,
					     );
	SVN::Repos::dir_delta ($fs->revision_root (0), $sanchor, $starget,
			       $fs->revision_root ($self->{rev}), $src->{path},
			       $editor, undef,
			       1, 1, 0, 1);
	$self->{xd}{checkout}->store_recursively ($dst->{copath}, {'.schedule' => undef,
								   '.newprop' => undef});
	$self->{xd}{checkout}->store ($dst->{copath}, {'.schedule' => 'add',
						       scheduleanchor => $dst->{copath},
						       '.copyfrom' => $src->{path},
						       '.copyfrom_rev' => $self->{rev}});
    }
    else {
	return unless $self->check_mirrored_path ($dst);
	$self->get_commit_message ();
	$self->do_copy_direct ( author => $ENV{USER},
				%$src,
				dpath => $dst->{path},
				%$self,
			      );
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Copy - Make a versioned copy

=head1 SYNOPSIS

 copy DEPOTPATH1 DEPOTPATH2
 copy DEPOTPATH1 PATH

=head1 OPTIONS

 -m [--message] arg:     Needs description
 -C [--check-only]:      Needs description
 -s [--sign]:            Needs description
 -r [--revision] arg:    Needs description
 --force:                Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
