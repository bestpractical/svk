package SVK::Command::Update;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 1;
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( HAS_SVN_MIRROR );

sub options {
    ('r|revision=s'    => 'rev',
     's|sync'          => 'sync',
     'm|merge'         => 'merge',
     'q|quiet'         => 'quiet',
     'C|check-only'    => 'check_only',
     'I|incremental'   => 'incremental', # -- XXX unsafe -- undocumented XXX --
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_copath ($_)} @arg;
}

sub lock {
    my ($self, @arg) = @_;
    $self->lock_target ($_) for @arg;
}

sub run {
    my ($self, @arg) = @_;

    die loc ("--check-only cannot be used in conjunction with --merge.\n")
        if defined $self->{check_only} && $self->{merge};

    die loc ("--revision cannot be used in conjunction with --sync or --merge.\n")
	if defined $self->{rev} && ($self->{merge} || $self->{sync});

    for my $target (@arg) {
	my $update_target = SVK::Target->new
	    ( %$target,
	      path => $self->{update_target_path} || $target->{path},
	      revision => defined $self->{rev} ? $self->resolve_revision($target->clone,$self->{rev}) : $target->{repos}->fs->youngest_rev,
	      copath => undef
	    );

        # Because merging under the copy anchor is unsafe, we always merge
        # to the most immediate copy anchor under copath root.
        my ($merge_target, $copied_from) = $self->find_checkout_anchor (
            $target, $self->{merge}, $self->{sync}
        );

        my $sync_target = $copied_from || $merge_target;
        delete $self->{merge} if !$copied_from;

        if ($self->{sync}) {
            die loc("cannot load SVN::Mirror") unless HAS_SVN_MIRROR;

            # Because syncing under the mirror anchor is impossible,
            # we always sync from the mirror anchor.
            my ($m, $mpath) = SVN::Mirror::is_mirrored (
                $sync_target->{repos},
                $sync_target->{path}
            );
            $m->run if $m->{source};
        }

        if ($self->{merge}) {
            $self->command (
                smerge => {
                    ($self->{incremental} ? () : (message => '', log => 1)),
                    %$self, sync => 0,
                }
            )->run (
                $merge_target->copied_from($self->{sync}) => $merge_target
            );
        }
	$update_target->refresh_revision if $self->{sync} || $self->{merge};

	$self->do_update ($target, $update_target);
    }
    return;
}

sub do_update {
    my ($self, $cotarget, $update_target) = @_;
    my ($xdroot, $newroot) = map { $_->root ($self->{xd}) } ($cotarget, $update_target);
    # unanchorified
    my ($path, $copath) = @{$cotarget}{qw/path copath/};
    my $report = $cotarget->{report};
    my $kind = $newroot->check_path ($update_target->{path});
    die loc("path %1 does not exist.\n", $update_target->{path})
	if $kind == $SVN::Node::none;

    print loc("Syncing %1(%2) in %3 to %4.\n", @{$cotarget}{qw( depotpath path copath )},
	      $update_target->{revision});
    if ($kind == $SVN::Node::file ) {
	$cotarget->anchorify;
	$update_target->anchorify;
	# can't use $cotarget->{path} directly since the (rev0, /) hack
	($path, $copath) = @{$cotarget}{qw/path copath/};
	$cotarget->{targets}[0] = $cotarget->{copath_target};
    }
    my $base = $cotarget;
    $base = $base->new (path => '/')
	if $xdroot->check_path ($base->path) == $SVN::Node::none;
    unless (-e $cotarget->{copath}) {
	die loc ("Checkout directory gone. Use 'checkout %1 %2' instead.\n",
		 $update_target->{depotpath}, $cotarget->{report})
	    unless $base->{path} eq '/';
	mkdir ($cotarget->{copath}) or
	    die loc ("Can't create directory %1 for checkout: %2.\n", $cotarget->{report}, $!);
    }

    my $notify = SVK::Notify->new_with_report
	($report, $cotarget->{targets}[0], 1);
    $notify->{quiet}++ if $self->{quiet};
    my $merge = SVK::Merge->new
	(repos => $cotarget->{repos}, base => $base, base_root => $xdroot,
	 no_recurse => !$self->{recursive}, notify => $notify, nodelay => 1,
	 src => $update_target, dst => $cotarget, check_only => $self->{check_only},
	 auto => 1, # not to print track-rename hint
	 xd => $self->{xd});
    $merge->run ($self->{xd}->get_editor (copath => $copath, path => $path,
					  store_path => $update_target->path,
					  check_only => $self->{check_only},
					  ignore_checksum => 1,
					  oldroot => $xdroot, newroot => $newroot,
					  revision => $update_target->{revision},
					  anchor => $cotarget->{path},
					  target => $cotarget->{targets}[0] || '',
					  update => $self->{check_only} ? 0 : 1));
}

1;

__DATA__

=head1 NAME

SVK::Command::Update - Bring changes from repository to checkout copies

=head1 SYNOPSIS

 update [PATH...]

=head1 OPTIONS

 -r [--revision] REV    : act on revision REV instead of the head revision
 -N [--non-recursive]   : do not descend recursively
 -C [--check-only]      : try operation but make no changes
 -s [--sync]            : synchronize mirrored sources before update
 -m [--merge]           : smerge from copied sources before update
 -q [--quiet]           : quiet mode

=head1 DESCRIPTION

Synchronize checkout copies to revision given by -r or to HEAD
revision by default.

For each updated item a line will start with a character reporting the
action taken. These characters have the following meaning:

  A  Added
  D  Deleted
  U  Updated
  C  Conflict
  G  Merged
  g  Merged without actual change

A character in the first column signifies an update to the actual
file, while updates to the file's props are shown in the second
column.

If both C<--sync> and C<--merge> are specified, like in C<svk up -sm>,
it will first synchronize the mirrored copy source path, and then smerge
from it.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
