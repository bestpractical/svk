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

sub mkpdir {
    my ($self, $target, $root, $yrev) = @_;
    my $edit = SVN::Simple::Edit->new
	(_editor => [SVN::Repos::get_commit_editor
		     ( $target->{repos},
		       "file://$target->{repospath}",
		       '/', $ENV{USER},
		       "directory for svk import",
		       sub { print loc("Import path %1 initialized.\n", $target->{path}) })],
	 pool => SVN::Pool->new,
	 missing_handler => &SVN::Simple::Edit::check_missing ($root));
    $edit->open_root ($yrev);
    $edit->add_directory ($target->{path});
    $edit->close_edit;
}

sub run {
    my ($self, $target, $copath) = @_;

    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my $root = $fs->revision_root ($yrev);
    my $kind = $root->check_path ($target->{path});

    die loc("import destination cannot be a file") if $kind == $SVN::Node::file;

    if ($kind == $SVN::Node::none) {
	$self->mkpdir ($target, $root, $yrev);
	$yrev = $fs->youngest_rev;
	$root = $fs->revision_root ($yrev);
    }

    if (exists $self->{xd}{checkout}->get ($copath)->{depotpath}) {
	$self->{is_checkout}++;
	die loc("Import source cannot be a checkout path")
	    unless $self->{force};
	# XXX: check if anchor matches
	my (undef, $path) = $self->{xd}->find_repos_from_co ($copath, 0);
	die loc("Import path ($target->{path}) is different from the copath ($path)\n")
	    unless $path eq $target->{path};

    }
    else {
	$self->{xd}{checkout}->store
	    ($copath, {depotpath => $target->{depotpath},
		       '.newprop' => undef,
		       '.conflict' => undef,
		       revision => $target->{revision}});
    }

    $self->get_commit_message () unless $self->{check_only};
    my ($editor, %cb) = $self->get_editor ($target);
    ${$cb{callback}} =
	sub { $yrev = $_[0];
	      print loc("Directory %1 imported to depotpath %2 as revision %3.\n",
			$copath, $target->{depotpath}, $yrev);

	      if ($self->{is_checkout}) {
		  $self->committed_import ($copath)->($yrev);
	      }
	      else {
		  $self->{xd}{checkout}->store
		      ($copath, {depotpath => undef,
				 revision => undef,
				 '.schedule' => undef});
	      }
	  };

    $self->{import} = 1;
    $self->run_delta ($target->new (copath => $copath), $root, $editor, %cb);
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
