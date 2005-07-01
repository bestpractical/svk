package SVK::Command::Commit;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command );
use constant opt_recursive => 1;
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Status;
use SVK::Editor::Sign;
use SVK::Command::Sync;
use SVK::Util qw( HAS_SVN_MIRROR get_buffer_from_editor slurp_fh read_file
		  find_svm_source tmpfile abs2rel find_prev_copy from_native to_native
		  get_encoder );

sub options {
    ('m|message=s'  => 'message',
     'F|file=s'     => 'message_file',
     'C|check-only' => 'check_only',
     'S|sign'	  => 'sign',
     'P|patch=s'  => 'patch',
     'import'	  => 'import',
     'encoding=s' => 'encoding',
     'direct'	  => 'direct',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_condensed (@arg);
}

sub lock { $_[0]->lock_target ($_[1]) }

sub target_prompt {
    loc('=== Targets to commit (you may delete items from it) ===');
}

sub message_prompt {
    loc('=== Please enter your commit message above this line ===');
}

sub under_mirror {
    my ($self, $target) = @_;
    return if $self->{direct};
    HAS_SVN_MIRROR and SVN::Mirror::is_mirrored ($target->{repos}, $target->{path});
}

sub fill_commit_message {
    my $self = shift;
    if ($self->{message_file}) {
	die loc ("Can't use -F with -m.\n")
	    if defined $self->{message};
	$self->{message} = read_file ($self->{message_file});
    }
}

sub get_commit_message {
    my ($self, $msg) = @_;
    $self->fill_commit_message;
    unless (defined $self->{message}) {
	$self->{message} = get_buffer_from_editor
	    (loc('log message'), $self->message_prompt,
	     join ("\n", $msg || '', $self->message_prompt, ''), 'commit');
	++$self->{save_message};
    }
    $self->decode_commit_message;
}

sub decode_commit_message {
    my $self = shift;
    eval { from_native ($self->{message}, 'commit message', $self->{encoding}); 1 }
	or die $@.loc("try --encoding.\n");
}

# XXX: This should just return Editor::Dynamic objects
sub get_dynamic_editor {
    my ($self, $target) = @_;
    my $m = $self->under_mirror ($target);
    my $anchor = $m ? $m->{target_path} : '/';
    my ($storage, %cb) = $self->get_editor ($target->new (path => $anchor));
    my $editor = SVK::Editor::Rename->new
	( editor => $storage,
	  cb_exist => $self->{parent} ? $cb{cb_exist} : undef);
    $editor->{_root_baton} = $editor->open_root ($cb{cb_rev}->(''));
    return ($anchor, $editor);
}

sub finalize_dynamic_editor {
    my ($self, $editor) = @_;
    $editor->close_directory ($editor->{_root_baton});
    $editor->close_edit;
    delete $self->{save_message};
}

sub adjust_anchor {
    my ($self, $editor) = @_;
    $editor->adjust_anchor ($editor->{edit_tree}[0][-1]);
}

sub save_message {
    my $self = shift;
    return unless $self->{save_message};
    local $@;
    my ($fh, $file) = tmpfile ('commit', DIR => '', TEXT => 1, UNLINK => 0);
    print $fh $self->{message};
    print loc ("Commit message saved in %1.\n", $file);
}

# Return the editor according to copath, path, and is_mirror (path)
# It will be Editor::XD, repos_commit_editor, or svn::mirror merge back editor.
sub get_editor {
    my ($self, $target, $callback, $source) = @_;
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
	if ($self->{patch}) {
	    print loc("Patching locally against mirror source %1.\n", $m->{source});
	    $base_rev = $m->{fromrev};
	}
	elsif ($self->{check_only}) {
	    print loc("Checking locally against mirror source %1.\n", $m->{source});
	}
	else {
	    print loc("Merging back to mirror source %1.\n", $m->{source});
	    $m->{lock_message} = SVK::Command::Sync::lock_message ();
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

    %cb = SVK::Editor::Merge->cb_for_root
	($root, $target->{path}, defined $base_rev ? $base_rev : $yrev);

    if ($self->{patch}) {
	require SVK::Patch;
	die loc ("Illegal patch name: %1.\n", $self->{patch})
	    if $self->{patch} =~ m!/!;
	my $patch = SVK::Patch->new ($self->{patch}, $self->{xd},
				     $target->depotname, $source, $target->new (targets => undef));
	$patch->ticket (SVK::Merge->new (xd => $self->{xd}), $source, $target)
	    if $source;
	$patch->{log} = $self->{message};
	my $fname = $self->{xd}->patch_file ($self->{patch});
	if (-e $fname) {
	    die loc ("file %1 already exists.\n", $fname).
		($source ? loc ("use 'svk patch regen %1' instead.\n", $self->{patch}) : '');
	}
	return ($patch->commit_editor ($fname), %cb, callback => \$callback,
		send_fulltext => 0);
    }

    $editor ||= $self->{check_only} ? SVN::Delta::Editor->new :
	SVN::Delta::Editor->new
	( $target->{repos}->get_commit_editor
	  ( "file://$target->{repospath}",
	    $target->{path}, $ENV{USER}, $self->{message},
	    sub { print loc("Committed revision %1.\n", $_[0]);
		  $fs->change_rev_prop ($_[0], 'svk:signature',
					$self->{signeditor}{sig})
		      if $self->{sign};
		  # build the copy cache as early as possible
		  find_prev_copy ($fs, $_[0]);
		  $callback->(@_) if $callback; }
	  ));

    if ($self->{sign}) {
	my ($uuid, $dst) = find_svm_source ($target->{repos}, $target->{path});
	$self->{signeditor} = $editor = SVK::Editor::Sign->new (_editor => [$editor],
								anchor => "$uuid:$dst"
							       );
    }

    unless ($self->{check_only}) {
	for ($SVN::Error::FS_TXN_OUT_OF_DATE,
	     $SVN::Error::FS_CONFLICT,
	     $SVN::Error::FS_ALREADY_EXISTS,
	     $SVN::Error::FS_NOT_DIRECTORY,
	     $SVN::Error::RA_DAV_REQUEST_FAILED,
	    ) {
	    # XXX: this error should actually be clearer in the destructor of $editor.
	    $self->clear_handler ($_);
	    # XXX: there's no copath info here
	    $self->msg_handler ($_, $m ? "Please sync mirrored path $target->{path} first."
				       : "Please update checkout first.");
	    $self->add_handler ($_, sub { $editor->abort_edit });
	}
    }

    return ($editor, %cb, mirror => $m, callback => \$callback,
	    send_fulltext => !$m);
}

sub exclude_mirror {
    my ($self, $target) = @_;
    return () if $self->{direct} or !HAS_SVN_MIRROR;

    ( exclude => {
	map { substr ($_, length($target->{path})) => 1 }
	    $target->contains_mirror },
    );
}

sub get_committable {
    my ($self, $target, $root) = @_;
    my ($fh, $file);
    $self->fill_commit_message;
    unless (defined $self->{message}) {
	($fh, $file) = tmpfile ('commit', TEXT => 1, UNLINK => 0);
    }

    print $fh "\n", $self->target_prompt, "\n" if $fh;

    my $targets = [];
    my $encoder = get_encoder;
    my $statuseditor = SVK::Editor::Status->new
	( notify => SVK::Notify->new
	  ( cb_flush => sub {
		my ($path, $status) = @_;
		to_native ($path, 'path', $encoder);
		my $copath = $target->copath ($path);
		push @$targets, [$status->[0] || ($status->[1] ? 'P' : ''),
				 $copath];
		    no warnings 'uninitialized';
		print $fh sprintf ("%1s%1s%1s \%s\n", @{$status}[0..2], $copath) if $fh;
	    }));
    $self->{xd}->checkout_delta
	( %$target,
	  depth => $self->{recursive} ? undef : 0,
	  $self->exclude_mirror ($target),
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

        # get_buffer_from_editor may modify it, so it must be a ref first
        $target->{targets} ||= [];

	($self->{message}, $targets) =
	    get_buffer_from_editor (loc('log message'), $self->target_prompt,
				    undef, $file, $target->{copath}, $target->{targets});
	die loc("No targets to commit.\n") if $#{$targets} < 0;
	++$self->{save_message};
	unlink $file;
    }
    $self->decode_commit_message;
    return [sort {$a->[1] cmp $b->[1]} @$targets];
}

sub committed_commit {
    my ($self, $target, $targets) = @_;
    my $fs = $target->{repos}->fs;
    sub {
	my $rev = shift;
	my ($entry, $dataroot) = $self->{xd}{checkout}->get ($target->{copath});
	my (undef, $coanchor) = $self->{xd}->find_repos ($entry->{depotpath});
	my $oldroot = $fs->revision_root ($rev-1);
	# optimize checkout map
	for my $copath ($self->{xd}{checkout}->find ($dataroot, {revision => qr/.*/})) {
	    my $coinfo = $self->{xd}{checkout}->get ($copath);
	    next if $coinfo->{'.deleted'};
	    my $corev = $coinfo->{revision};
	    # XXX: cache the node_created_rev for entries within $target->path
	    next if $corev < $oldroot->node_created_rev (abs2rel ($copath, $dataroot => $coanchor, '/'));
	    $self->{xd}{checkout}->store_override ($copath, {revision => $rev});
	}
	# update checkout map with new revision
	for (reverse @$targets) {
	    my ($action, $path) = @$_;
	    my $store = $self->{recursive} ? 'store_recursively' : 'store';
	    $self->{xd}{checkout}->$store ($path, { $self->_schedule_empty });
            if (($action eq 'D') and $self->{xd}{checkout}->get ($path)->{revision} == $rev ) {
                # Fully merged, remove the special node
                $self->{xd}{checkout}->store (
                    $path, { revision => undef, $self->_schedule_empty }
                );
            }
            else {
                $self->{xd}{checkout}->store (
                    $path, {
                        revision => $rev,
                        ($action eq 'D') ? ('.deleted' => 1) : (),
                    }
                )
            }
	}
	my $root = $fs->revision_root ($rev);
	# update keyword-translated files
	my $encoder = get_encoder;
	for (@$targets) {
	    my ($action, $copath) = @$_;
	    next if $action eq 'D' || -d $copath;
	    my $path = $target->{path};
	    $path = '' if $path eq '/';
	    my $dpath = abs2rel($copath, $target->{copath} => $path, '/');
	    from_native ($dpath, 'path', $encoder);
	    my $prop = $root->node_proplist ($dpath);
	    my $layer = SVK::XD::get_keyword_layer ($root, $dpath, $prop);
	    my $eol = SVK::XD::get_eol_layer ($prop, '>');
	    # XXX: can't bypass eol translation when normalization needed
	    next unless $layer || ($eol ne ':raw' && $eol ne ' ');

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
	if $is_mirrored and !$self->{patch};

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
	if $is_mirrored and !($self->{direct} or $self->{patch} or $cb{mirror});

    $self->run_delta ($target, $xdroot, $editor, %cb);
}

sub run_delta {
    my ($self, $target, $xdroot, $editor, %cb) = @_;
    my $fs = $target->{repos}->fs;
    my %revcache;
    $self->{xd}->checkout_delta
	( %$target,
	  depth => $self->{recursive} ? undef : 0,
	  xdroot => $xdroot,
	  editor => $editor,
	  send_delta => !$cb{send_fulltext},
	  nodelay => $cb{send_fulltext},
	  $self->exclude_mirror ($target),
	  cb_exclude => sub { print loc ("%1 is a mirrored path, please commit separately.\n",
					 abs2rel ($_[1], $target->{copath} => $target->{report})) },
	  $self->{import} ?
	  ( auto_add => 1,
	    obstruct_as_replace => 1,
	    absent_as_delete => 1) :
	  ( absent_ignore => 1),
	  $cb{mirror} ?
	  ( cb_copyfrom => sub {
		my ($path, $rev) = @_;
		$path =~ s|^\Q$cb{mirror}{target_path}\E|$cb{mirror}{source}|;
		return ($path, scalar $cb{mirror}->find_remote_rev ($rev));
	    },
	    cb_rev => sub {
		my $revtarget = shift;
		my $cotarget = $target->copath ($revtarget);
		$revtarget = $revtarget ? "$target->{path}/$revtarget" : $target->{path};
		my $entry = $self->{xd}{checkout}->get($cotarget);
		my ($source_path, $source_rev) = $self->{xd}->_copy_source ($entry, $cotarget);
		($source_path, $source_rev) = ($revtarget, $entry->{revision})
		    unless defined $source_path;
		return $revcache{$source_rev} if exists $revcache{$source_rev};
		my $rev = ($fs->revision_root ($source_rev)->node_history ($source_path)->prev (0)->location)[1];
		$revcache{$source_rev} = $cb{mirror}->find_remote_rev ($rev);
	    }) : ());
    delete $self->{save_message};
    return;
}

sub DESTROY {
    $_[0]->save_message;
}

1;

__DATA__

=head1 NAME

SVK::Command::Commit - Commit changes to depot

=head1 SYNOPSIS

 commit [PATH...]

=head1 OPTIONS

 -m [--message] MESSAGE	: specify commit message MESSAGE
 -F [--file] FILENAME	: read commit message from FILENAME
 -C [--check-only]      : try operation but make no changes
 -P [--patch] NAME	: instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -N [--non-recursive]   : operate on single directory only
 --encoding ENC         : treat value as being in charset encoding ENC
 --import               : import mode; automatically add and delete nodes
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
