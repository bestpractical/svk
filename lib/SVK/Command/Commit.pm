package SVK::Command::Commit;
use strict;
our $VERSION = '0.13';
use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::CommitStatusEditor;
use SVK::SignEditor;
use SVK::Util qw(get_buffer_from_editor slurp_fh find_svm_source svn_mirror);
use File::Temp;
use SVN::Simple::Edit;

my $target_prompt = '=== below are targets to be committed ===';

my $auth;

sub options {
    ('m|message=s'  => 'message',
     'C|check-only' => 'check_only',
     's|sign'	  => 'sign',
     'force',	  => 'force'
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_condensed (@arg);
}

sub lock {
    my ($self, $arg) = @_;
    $arg->{copath} ? $self->lock_target ($arg) : $self->lock_none;
}

sub target_prompt { $target_prompt }

sub auth {
    eval 'require SVN::Client' or die $@;
    $auth ||= SVN::Core::auth_open
	([SVN::Client::get_simple_provider (),
	  SVN::Client::get_ssl_server_trust_file_provider (),
	  SVN::Client::get_username_provider ()]);
}

sub path_is_mirrored {
    my ($self, $repos, $path) = @_;
    my $fs = $repos->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);

    my $rev = (($root->node_history ($path)->prev (0)->location)[1]);
    return (grep {m/^svm:headrev:/} sort keys %{$fs->revision_proplist ($rev)});
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
	 missing_handler =>
	 SVN::Simple::Edit::check_missing ($xdroot));
}

sub get_commit_message {
    my ($self) = @_;
    $self->{message} = get_buffer_from_editor ('log message', $target_prompt,
					       "\n$target_prompt\n",
					       "/tmp/svk-commitXXXXX")
	unless defined $self->{message};
}

# Return the editor according to copath, path, and is_mirror (path)
# It will be XD::Editor, repos_commit_editor, or svn::mirror merge back editor.
sub get_editor {
    my ($self, $target) = @_;
    my ($callback, $editor, %cb);

    # XXX: the case that the target is an xd is actually only used in merge.
    if ($target->{copath}) {
	my $xdroot = $self->{xd}->xdroot (%$target);
	($editor, %cb) = $self->{xd}->get_editor
	    ( %$target,
	      oldroot => $xdroot,
	      newroot => $xdroot,
	      anchor => $target->{path},
	      target => '',
	      check_only => $self->{check_only});
	return ($editor, %cb);
    }

    my ($base_rev, $m, $mpath);

    if (svn_mirror && (($m, $mpath) = SVN::Mirror::is_mirrored ($target->{repos}, $target->{path}))) {
	print loc("Merging back to SVN::Mirror source %1.\n", $m->{source});
	if ($self->{check_only}) {
	    print loc("Checking against mirrored directory locally.\n");
	}
	else {
	    $m->{auth} = $self->auth;
	    $m->{revprop} = ['svk:signature'];
	    ($base_rev, $editor) = $m->get_merge_back_editor
		($mpath, $self->{message},
		 sub { print loc("Merge back committed as revision %1.\n", $_[0]);
		       my $rev = shift;
		       $m->_new_ra->change_rev_prop ($rev, 'svk:signature',
						     $self->{signeditor}{sig})
			   if $self->{sign};
		       $m->run ($rev);
		       &{$callback} ($m->find_local_rev ($rev), @_)
			   if $callback }
		);
	    $base_rev = $m->{fromrev};
	}
    }

    my $fs = $target->{repos}->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);

    $editor ||= SVN::Delta::Editor->new
	( SVN::Repos::get_commit_editor
	  ( $target->{repos}, "file://$target->{repospath}",
	    $target->{path}, $ENV{USER}, $self->{message},
	    sub { print loc("Committed revision %1.\n", $_[0]);
		  $fs->change_rev_prop ($_[0], 'svk:signature',
					$self->{signeditor}{sig})
		      if $self->{sign};
		  &{$callback} (@_) if $callback; }
	  ));
    $base_rev ||= $target->{repos}->fs->youngest_rev;

    if ($self->{sign}) {
	my ($uuid, $dst) = find_svm_source ($target->{repos}, $target->{path});
	$self->{signeditor} = $editor = SVK::SignEditor->new (_editor => [$editor],
							      anchor => "$uuid:$dst"
							     );
    }

    $editor = SVK::XD::CheckEditor->new ($editor)
	if $self->{check_only};

    %cb = ( cb_exist => $self->{cb_exist} ||
	    sub { my $path = $target->{path}.'/'.shift;
		  $root->check_path ($path) != $SVN::Node::none;
	      },
	    cb_rev => sub { $base_rev; },
	    cb_conflict => sub { die loc("conflict on %1", "$target->{path}/$_[0]")
				     unless $self->{check_only};
				 $editor->{conflicts}++;
			     },
	    cb_localmod => $self->{cb_localmod} ||
	    sub { my ($path, $checksum, $pool) = @_;
		  $path = "$target->{path}/$path";
		  my $md5 = $root->file_md5_checksum ($path, $pool);
		  return if $md5 eq $checksum;
		  return [$root->file_contents ($path, $pool),
			  undef, $md5];
	      },
	  );

    return ($editor, %cb, mirror => $m, callback => \$callback);
}


sub run {
    my ($self, $target) = @_;

    my $is_mirrored;
    $is_mirrored = $self->path_is_mirrored ($target->{repos}, $target->{path})
	if svn_mirror;
    print loc("Commit into mirrored path: merging back directly.\n")
	if $is_mirrored;

    my ($fh, $file);
    my $xdroot = $self->{xd}->xdroot (%$target);

    unless (defined $self->{message}) {
	($fh, $file) = mkstemps("svk-commitXXXXX", '.tmp');
    }

    print $fh "\n$target_prompt\n" if $fh;

    my $targets = [];
    $self->{xd}->checkout_delta
	( %$target,
	  baseroot => $xdroot,
	  xdroot => $xdroot,
	  nodelay => 1,
	  delete_verbose => 1,
	  absent_ignore => 1,
	  editor => SVK::CommitStatusEditor->new
	  ( copath => $target->{copath},
	    dpath => $target->{path},
	    targets => $targets, fh => $fh),
	  cb_conflict => \&SVK::StatusEditor::conflict,
	);

    my $conflicts = grep {$_->[0] eq 'C'} @$targets;
    if ($conflicts) {
	if ($fh) {
	    close $fh;
	    unlink $fh;
	}
	print loc("%*(%1,conflict) detected. Use 'svk resolved' after resolving them.\n", $conflicts);
	return;
    }

    die loc("no targets to commit") if $#{$targets} < 0;

    if ($fh) {
	close $fh;
	($self->{message}, $targets) =
	    get_buffer_from_editor ('log message', $target_prompt,
				    undef, $file, $target->{copath}, $target->{targets});
    }

    # if $copath itself is a file or is in the targets,
    # should get the anchor instead, tweak copath for the s// in XD.pm

    $targets = [sort {$a->[1] cmp $b->[1]} @$targets];

    my ($editor, %cb) = $self->get_editor ({%$target, copath => undef});

    my $committed = sub {
	my ($rev) = @_;
	my (undef, @datapoint) = $self->{xd}{checkout}->get ($target->{copath});
	my $fs = $target->{repos}->fs;
	for (reverse @$targets) {
	    my $store = ($_->[0] eq 'D' || -d $_->[1]) ?
		'store_recursively' : 'store';
	    $self->{xd}{checkout}->$store ($_->[1], { '.schedule' => undef,
						      '.newprop' => undef,
						      $_->[0] eq 'D' ? ('.deleted' => 1) : (),
						      revision => $rev,
						    });
	}
	my $oldroot = $fs->revision_root ($rev-1);
	my $oldrev = $oldroot->node_created_rev ($target->{path});
	for (@datapoint) {
	    # use store_single to effectively override all the oldvalue but not others.
	    for my $path ($self->{xd}{checkout}->find ($_, {revision => qr/.*/})) {
		next unless $self->{xd}{checkout}->get ($path)->{revision} >= $oldrev;
		# XXX: should be a data::hierarchy api to simply do this and remove
		# duplicates
		$self->{xd}{checkout}->store_override ($path, {revision => $rev});
		$self->{xd}{checkout}->store ($path, {'.deleted' => undef});
	    }
	}
	my $root = $fs->revision_root ($rev);
	for (@$targets) {
	    next if $_->[0] eq 'D';
	    my ($action, $tpath) = @$_;
	    my $cpath = $tpath;
	    $tpath =~ s|^\Q$target->{copath}\E||;
	    my $layer = SVK::XD::get_keyword_layer ($root, "$target->{path}/$tpath");
	    next unless $layer;

	    my $fh = SVK::XD::get_fh ($xdroot, '<', "$target->{path}/$tpath", $cpath, $layer);
	    # XXX: beware of collision
	    # XXX: fix permission etc also
	    my $fname = "$cpath.svk.old";
	    rename $cpath, $fname;
	    open my ($newfh), ">", $cpath;
	    $layer->via ($newfh) if $layer;
	    slurp_fh ($fh, $newfh);
	    close $fh;
	    unlink $fname;
	}
    };

    die loc("unexpected error: commit to mirrored path but no mirror object")
	if $is_mirrored && !$cb{mirror};

    ${$cb{callback}} = $committed;

    $self->{xd}->checkout_delta
	( %$target,
	  baseroot => $xdroot,
	  xdroot => $xdroot,
	  absent_ignore => 1,
	  editor => $editor,
	  $cb{mirror} ?
	  ( send_delta => 1,
	    cb_rev => sub {
		my $revtarget = shift;
		my $cotarget = $revtarget;
		my $fs = $target->{repos}->fs;
		$cotarget = $cotarget ? "$target->{copath}/$cotarget" : $target->{copath};
		$revtarget = $revtarget ? "$target->{path}/$revtarget" : $target->{path};

		my $root = $fs->revision_root
		    ($self->{xd}{checkout}->get($cotarget)->{revision});
		$fs->revision_prop ($root->node_created_rev ($revtarget),
				    "svm:headrev:$cb{mirror}{source}");
	    }) : ());
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Commit - Commit changes to depot

=head1 SYNOPSIS

    commit [PATH...]

=head1 OPTIONS

    options:
    -m [--message] ARG:    specify commit message ARG
    -s [--sign]:           sign the commit
    -C [--check-only]:	Needs description
    --force:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
