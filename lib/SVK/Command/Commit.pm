package SVK::Command::Commit;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Status;
use SVK::Editor::Sign;
use SVK::Util qw( HAS_SVN_MIRROR get_buffer_from_editor slurp_fh find_svm_source tmpfile abs2rel );
use SVN::Simple::Edit;

my $target_prompt = '=== below are targets to be committed ===';

sub options {
    ('m|message=s'  => 'message',
     'C|check-only' => 'check_only',
     's|sign'	  => 'sign',
     'import',	  => 'import',
     'direct',	  => 'direct',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_condensed (@arg);
}

sub lock { $_[0]->lock_target ($_[1]) }

sub target_prompt { $target_prompt }

sub under_mirror {
    my ($self, $target) = @_;
    HAS_SVN_MIRROR and SVN::Mirror::is_mirrored ($target->{repos}, $target->{path});
}

sub check_mirrored_path {
    my ($self, $target) = @_;
    if (!$self->{direct} && $self->under_mirror ($target)) {
	print loc ("%1 is under mirrored path, use --direct to override.\n",
		    $target->{depotpath});
	return;
    }
    return 1;
}

sub get_commit_editor {
    my ($self, $xdroot, $committed, $path, %arg) = @_;
    ${$arg{callback}} = $committed if $arg{editor};
    return SVN::Simple::Edit->new
	(_editor => [$arg{editor} ||
		     SVN::Repos::get_commit_editor($arg{repos},
						   "file://$arg{repospath}",
						   $path,
						   $arg{author}, $arg{message},
						   $committed)],
	 base_path => $path,
	 $arg{mirror} ? () : ( root => $xdroot ),
	 pool => SVN::Pool->new,
	 missing_handler =>
	 SVN::Simple::Edit::check_missing ($xdroot));
}

sub get_commit_message {
    my ($self, $msg) = @_;
    return if defined $self->{message};
    $self->{message} = get_buffer_from_editor
	(loc('log message'), $target_prompt, join ("\n", $msg || '', $target_prompt, ''), 'commit');
}

# Return the editor according to copath, path, and is_mirror (path)
# It will be Editor::XD, repos_commit_editor, or svn::mirror merge back editor.
sub get_editor {
    my ($self, $target, $callback) = @_;
    my ($editor, %cb);

    # XXX: the case that the target is an xd is actually only used in merge.
    if ($target->{copath}) {
	my $xdroot = $target->root ($self->{xd});
	($editor, %cb) = $self->{xd}->get_editor
	    ( %$target,
	      # assuming the editor returned here are used with Editor::Merge
	      ignore_checksum => 1,
	      targets => undef,
	      quiet => 1,
	      oldroot => $xdroot,
	      newroot => $xdroot,
	      target => '',
	      check_only => $self->{check_only});
	return ($editor, %cb);
    }

    my ($base_rev, $m, $mpath);
    if (!$self->{direct} and HAS_SVN_MIRROR and
	(($m, $mpath) = SVN::Mirror::is_mirrored ($target->{repos}, $target->{path}))) {
	print loc("Merging back to SVN::Mirror source %1.\n", $m->{source});
	if ($self->{check_only}) {
	    print loc("Checking against mirrored directory locally.\n");
	}
	else {
	    $m->{config} = $self->{svnconfig};
	    $m->{revprop} = ['svk:signature'];
	    ($base_rev, $editor) = $m->get_merge_back_editor
		($mpath, $self->{message},
		 sub { print loc("Merge back committed as revision %1.\n", $_[0]);
		       my $rev = shift;
		       $m->_new_ra->change_rev_prop ($rev, 'svk:signature',
						     $self->{signeditor}{sig})
			   if $self->{sign};
		       $m->run ($rev);
		       $callback->($m->find_local_rev ($rev), @_)
			   if $callback }
		);
	}
    }

    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my $root = $fs->revision_root ($yrev);

    $editor ||= $self->{check_only} ? SVN::Delta::Editor->new :
	SVN::Delta::Editor->new
	( $target->{repos}->get_commit_editor
	  ( "file://$target->{repospath}",
	    $target->{path}, $ENV{USER}, $self->{message},
	    sub { print loc("Committed revision %1.\n", $_[0]);
		  $fs->change_rev_prop ($_[0], 'svk:signature',
					$self->{signeditor}{sig})
		      if $self->{sign};
		  $callback->(@_) if $callback; }
	  ));

    if ($self->{sign}) {
	my ($uuid, $dst) = find_svm_source ($target->{repos}, $target->{path});
	$self->{signeditor} = $editor = SVK::Editor::Sign->new (_editor => [$editor],
								anchor => "$uuid:$dst"
							       );
    }

    %cb = SVK::Editor::Merge::cb_for_root
	($root, $target->{path}, defined $base_rev ? $base_rev : $yrev);

    unless ($self->{check_only}) {
	for ($SVN::Error::FS_TXN_OUT_OF_DATE, $SVN::Error::FS_ALREADY_EXISTS) {
	    # XXX: there's no copath info here
	    $self->msg_handler ($_, $m ? "Please sync mirrored path $target->{path} first."
				       : "Please update checkout first.");
	    $self->add_handler ($_, sub { $editor->abort_edit });
	}
    }

    return ($editor, %cb, mirror => $m, callback => \$callback);
}


sub get_committable {
    my ($self, $target, $root) = @_;
    my ($fh, $file);
    unless (defined $self->{message}) {
	($fh, $file) = tmpfile ('commit', TEXT => 1, UNLINK => 0);
    }

    print $fh "\n$target_prompt\n" if $fh;

    my $targets = [];
    my $statuseditor = SVK::Editor::Status->new
	( notify => SVK::Notify->new
	  ( cb_flush => sub {
		my ($path, $status) = @_;
		my $copath = $target->copath ($path);
		push @$targets, [$status->[0] || ($status->[1] ? 'P' : ''),
				 $copath];
		    no warnings 'uninitialized';
		print $fh sprintf ("%1s%1s%1s \%s\n", @{$status}[0..2], $copath) if $fh;
	    }));
    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $root,
	  nodelay => 1,
	  delete_verbose => 1,
	  absent_ignore => 1,
	  editor => $statuseditor,
	  cb_conflict => \&SVK::Editor::Status::conflict,
	);

    my $conflicts = grep {$_->[0] eq 'C'} @$targets;

    if ($#{$targets} < 0 || $conflicts) {
	if ($fh) {
	    close $fh;
	    unlink $file;
	}
	die loc("No targets to commit.\n") if $#{$targets} < 0;
	die loc("%*(%1,conflict) detected. Use 'svk resolved' after resolving them.\n", $conflicts);
    }

    if ($fh) {
	close $fh;
	($self->{message}, $targets) =
	    get_buffer_from_editor (loc('log message'), $target_prompt,
				    undef, $file, $target->{copath}, $target->{targets});
	unlink $file;
    }

    return [sort {$a->[1] cmp $b->[1]} @$targets];
}

sub committed_commit {
    my ($self, $target, $targets) = @_;
    my $fs = $target->{repos}->fs;
    sub {
	my $rev = shift;
	my (undef, $dataroot) = $self->{xd}{checkout}->get ($target->{copath});
	my $oldroot = $fs->revision_root ($rev-1);
	my $oldrev = $oldroot->node_created_rev ($target->{path});
	# optimize checkout map
	for my $copath ($self->{xd}{checkout}->find ($dataroot, {revision => qr/.*/})) {
	    my $corev = $self->{xd}{checkout}->get ($copath)->{revision};
	    next if $corev < $oldrev;
	    $self->{xd}{checkout}->store_override ($copath, {revision => $rev});
	}
	# update checkout map with new revision
	for (reverse @$targets) {
	    my ($action, $path) = @$_;
	    $self->{xd}{checkout}->store_recursively ($path, { $self->_schedule_empty });
	    $self->{xd}{checkout}->store
		($path, { revision => $rev,
			  $action eq 'D' ? ('.deleted' => 1) : (),
			})
		    unless $self->{xd}{checkout}->get ($path)->{revision} == $rev;
	}
	my $root = $fs->revision_root ($rev);
	# update keyword-translated files
	for (@$targets) {
	    my ($action, $copath) = @$_;
	    next if $action eq 'D' || -d $copath;
	    my $path = $target->{path};
	    $path = '' if $path eq '/';
	    my $dpath = abs2rel($copath, $target->{copath} => $path, '/');
	    my $prop = $root->node_proplist ($dpath);
	    # XXX: some mode in get_fh for modification only
	    my $layer = SVK::XD::get_keyword_layer ($root, $dpath, $prop);
	    my $eol = SVK::XD::get_eol_layer ($root, $dpath, $prop);
	    next unless $layer || ($eol ne ':raw' && $eol ne '');

	    my $fh = $root->file_contents ($dpath);
	    my $perm = (stat ($copath))[2];
	    open my ($newfh), ">$eol", $copath or die $!;
	    $layer->via ($newfh) if $layer;
	    slurp_fh ($fh, $newfh);
	    chmod ($perm, $copath);
	}
    }
}

sub committed_import {
    my ($self, $copath) = @_;
    sub {
	my $rev = shift;
	$self->{xd}{checkout}->store_recursively
	    ($copath, {revision => $rev, $self->_schedule_empty});
    }
}

sub run {
    my ($self, $target) = @_;

    my $is_mirrored = $self->under_mirror ($target) && !$self->{direct};
    print loc("Commit into mirrored path: merging back directly.\n")
	if $is_mirrored;

    # XXX: should use some status editor to get the committed list for post-commit handling
    # while printing the modified nodes.
    my $xdroot = $target->root ($self->{xd});
    my $committed;
    if ($self->{import}) {
	$self->get_commit_message () unless $self->{check_only};
	$committed = $self->committed_import ($target->{copath});
    }
    else {
	$committed = $self->committed_commit ($target, $self->get_committable ($target, $xdroot));
    }

    my ($editor, %cb) = $self->get_editor ($target->new (copath => undef), $committed);

    die loc("unexpected error: commit to mirrored path but no mirror object")
	if $is_mirrored && !$self->{direct} && !$cb{mirror};

    $self->run_delta ($target, $xdroot, $editor, %cb);
}

sub run_delta {
    my ($self, $target, $xdroot, $editor, %cb) = @_;
    my $fs = $target->{repos}->fs;
    my %revcache;
    $self->{xd}->checkout_delta
	( %$target,
	  error => $self->{error},
	  xdroot => $xdroot,
	  editor => $editor,
	  $self->{import} ?
	  ( auto_add => 1,
	    absent_as_delete => 1) :
	  ( absent_ignore => 1),
	  $cb{mirror} ?
	  ( send_delta => 1,
	    cb_copyfrom => sub {
		my ($path, $rev) = @_;
		$path =~ s|^\Q$cb{mirror}{target_path}\E|$cb{mirror}{source}|;
		return ($path, scalar $cb{mirror}->find_remote_rev ($rev));
	    },
	    cb_rev => sub {
		my $revtarget = shift;
		my $cotarget = $target->copath ($revtarget);
		$revtarget = $revtarget ? "$target->{path}/$revtarget" : $target->{path};
		my $corev = $self->{xd}{checkout}->get($cotarget)->{revision};
		return $revcache{$corev} if exists $revcache{corev};
		my $rev = ($fs->revision_root ($corev)->node_history ($revtarget)->prev (0)->location)[1];
		$revcache{$corev} = $cb{mirror}->find_remote_rev ($rev);
	    }) :
	  ( nodelay => 1 ));
}

1;

__DATA__

=head1 NAME

SVK::Command::Commit - Commit changes to depot

=head1 SYNOPSIS

 commit [PATH...]

=head1 OPTIONS

 -m [--message] arg     : specify commit message ARG
 -C [--check-only]      : try operation but make no changes
 -s [--sign]            : sign this change
 --import               : import mode; automatically add and delete nodes
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
