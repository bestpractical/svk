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
			   $arg{revision});
    $edit->close_edit();
}

sub run {
    my ($self, $src, $dst) = @_;
    die loc("repos paths mismatch") unless $src->same_repos ($dst);
    $src->{revision} = $self->{rev} if defined $self->{rev};
    my $fs = $src->{repos}->fs;
    if ($dst->{copath}) {
	my $xdroot = $dst->root ($self->{xd});
	# XXX: prevent recursion, etc
	if (-d $dst->{copath}) {
	    # XXX: proper descendent
	    my ($name) = $src->{depotpath} =~ m|(/[^/]+)/?$|;
#	    $dst = $self->arg_copath ("$dst->{depotpath}$name");
	    $dst->{depotpath} .= $name;
	    $dst->{path} .= $name;
	    $dst->{copath} .= $name;
	}
	my $copath = $dst->{copath};
	$src->anchorify; $dst->anchorify;
	SVK::Merge->new
		(%$self, repos => $dst->{repos}, nodelay => 1,
		 report => $dst->{report},
		 base => $src->new (path => '/', revision => 0),
		 src => $src, dst => $dst)->run ($self->get_editor ($dst));

	$self->{xd}{checkout}->store_recursively ($copath, {'.schedule' => undef,
							    '.newprop' => undef});
	$self->{xd}{checkout}->store ($copath, {'.schedule' => 'add',
						scheduleanchor => $copath,
						'.copyfrom' => $src->path,
						'.copyfrom_rev' => $src->{revision}});
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
