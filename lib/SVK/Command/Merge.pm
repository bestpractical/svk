package SVK::Command::Merge;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Delay;
use SVK::Command::Log;
use SVK::Merge;
use SVK::Util qw (get_buffer_from_editor find_svm_source svn_mirror);

sub options {
    ($_[0]->SUPER::options,
     'a|auto'		=> 'auto',
     'l|log'		=> 'log',
     'no-ticket'	=> 'no_ticket',
     'r|revision=s'	=> 'revspec');
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

sub run {
    my ($self, $src, $dst) = @_;
    my ($fromrev, $torev, $baserev, $cb_merged, $cb_closed);

    die loc("repos paths mismatch") unless $src->{repospath} eq $dst->{repospath};
    my $repos = $src->{repos};
    unless ($self->{auto}) {
	die loc("revision required") unless $self->{revspec};
	($baserev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/
	    or die loc("revision must be N:M");
    }

    my $base_path = $src->{path};
    if ($self->{auto}) {
	$self->{merge} = SVK::Merge->new (%$self);
	($base_path, $baserev, $fromrev, $torev) =
	    ($self->{merge}->find_merge_base ($repos, $src->{path}, $dst->{path}), $repos->fs->youngest_rev);
	print loc("Auto-merging (%1, %2) %3 to %4 (base %5:%6).\n",
		  $fromrev, $torev, $src->{path}, $dst->{path}, $base_path, $baserev);
	$cb_merged = sub { my ($editor, $baton, $pool) = @_;
			   $editor->change_dir_prop
			       ($baton, 'svk:merge',
				$self->{merge}->get_new_ticket ($repos, $src->{path}, $dst->{path}));
		       } unless $self->{no_ticket};
    }

    unless ($dst->{copath} || defined $self->{message} || $self->{check_only}) {
	$self->{message} = get_buffer_from_editor
	    ('log message', $self->target_prompt,
	     ($self->{log} ?
	      $self->{merge}->log ($repos, $src->{path}, $fromrev+1, $torev) : '').
	     "\n".$self->target_prompt."\n", 'commit');
    }

    # editor for the target
    my ($storage, %cb) = $self->get_editor ($dst);

    my $fs = $repos->fs;
    $storage = SVK::Editor::Delay->new ($storage);
    my $editor = SVK::Editor::Merge->new
	( anchor => $src->{path},
	  base_anchor => $base_path,
	  base_root => $fs->revision_root ($baserev),
	  target => '',
	  send_fulltext => $cb{mirror} ? 0 : 1,
	  cb_merged => $cb_merged,
	  storage => $storage,
	  %cb,
	);
    $editor->{external} = $ENV{SVKMERGE}
	if $ENV{SVKMERGE} && -x $ENV{SVKMERGE} && !$self->{check_only};
    SVN::Repos::dir_delta ($fs->revision_root ($baserev),
			   $base_path, '',
			   $fs->revision_root ($torev), $src->{path},
			   $editor, undef,
			   1, 1, 0, 1);


    print loc("%*(%1,conflict) found.\n", $editor->{conflicts}) if $editor->{conflicts};

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Merge - Apply differences between two sources

=head1 SYNOPSIS

    merge -r N:M DEPOTPATH [PATH]
    merge -r N:M DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

    -r [--revision] rev:    revision
    -m [--message] message: commit message
    -C [--check-only]:      don't perform actual writes
    -a [--auto]:            automatically find merge points
    -l [--log]:             brings the logs of merged revs to the message buffer
    --no-ticket:            don't associate the ticket tracking merge history
    --force:		    Needs description
    -s [--sign]:	    Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
