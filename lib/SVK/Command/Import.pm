package SVK::Command::Import;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    $arg[1] = '' if $#arg < 1;

    return ($self->arg_depotpath ($arg[0]), $self->arg_path ($arg[1]));
}

sub lock {
    my ($self, $target, $source) = @_;
    return $self->lock_none
	unless $self->{xd}{checkout}->get ($source)->{depotpath};
    $source = $self->arg_copath ($source);
    ($self->{force} && $target->{path} eq $source->{path}) ?
	$self->lock_target ($source) : $self->lock_none;
}

sub run {
    my ($self, $target, $copath) = @_;

    $self->get_commit_message () unless $self->{check_only};

    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my $root = $fs->revision_root ($yrev);
    my $kind = $root->check_path ($target->{path});

    die loc("import destination cannot be a file") if $kind == $SVN::Node::file;

    if ($kind == $SVN::Node::none) {
	my $edit = SVN::Simple::Edit->new
	    (_editor => [SVN::Repos::get_commit_editor($target->{repos},
					    "file://$target->{repospath}",
					    '/', $ENV{USER},
					    "directory for svk import",
					    sub { print loc("Import path %1 initialized.\n", $target->{path}) })],
	     pool => SVN::Pool->new,
	     missing_handler => &SVN::Simple::Edit::check_missing ($root));

	$edit->open_root ($yrev);
	$edit->add_directory ($target->{path});
	$edit->close_edit;
	$yrev = $fs->youngest_rev;
	$root = $fs->revision_root ($yrev);
    }

    my ($editor, %cb) = $self->get_editor ($target);
    ${$cb{callback}} =
	sub { $yrev = $_[0];
	      print loc("Directory %1 imported to depotpath %2 as revision %3.\n",
			$copath, $target->{depotpath}, $yrev) };

    my $baton = $editor->open_root ($yrev);
    local $SIG{INT} = sub {
	$editor->abort_edit;
	die loc("Interrupted.\n");
    };
    if (exists $self->{xd}{checkout}->get ($copath)->{depotpath}) {
	$self->{is_checkout}++;
	die loc("Import source cannot be a checkout path")
	    unless $self->{force};
    }
    else {
	# XXX: check the entry first
	$self->{xd}{checkout}->store
	    ($copath, {depotpath => $target->{depotpath},
		       '.newprop' => undef,
		       '.conflict' => undef,
		       revision =>0});
    }

    $self->{xd}->_delta_dir
	( %$target,
	  copath => $copath,
	  auto_add => 1,
	  base => 1,
	  cb_rev => $cb{cb_rev},
	  editor => $editor,
	  base_root => $root,
	  base_path => $target->{path},
	  xdroot => $root,
	  kind => $SVN::Node::dir,
	  absent_as_delete => 1,
	  baton => $baton, root => 1);

    $editor->close_directory ($baton);
    $editor->close_edit ();

    if ($self->{is_checkout}) {
	my (undef, $path) = $self->{xd}->find_repos_from_co ($copath, 0);
	$self->{xd}{checkout}->store_recursively
	    ($copath, {revision => $yrev,
		       '.copyfrom' => undef,
		       '.copyfrom_rev' => undef,
		       '.newprop' => undef,
		       scheduleanchor => undef,
		       '.schedule' => undef})
	    if $path eq $target->{path};
    }
    else {
	$self->{xd}{checkout}->store
	    ($copath, {depotpath => undef,
		       revision => undef,
		       '.schedule' => undef});
    }
    return;
}


1;

__DATA__

=head1 NAME

SVK::Command::Import - Import directory into depot

=head1 SYNOPSIS

 import DEPOTPATH [PATH]

=head1 OPTIONS

 -m [--message] message:    commit message
 -C [--check-only]:         don't perform actual writes
 -s [--sign]:               Needs description
 --force:                   Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
