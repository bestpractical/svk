package SVK::Command::Commit;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Status;
use SVK::Editor::Sign;
use SVK::Util qw(get_buffer_from_editor slurp_fh find_svm_source svn_mirror tmpfile);
use SVN::Simple::Edit;

my $target_prompt = '=== below are targets to be committed ===';

sub options {
    ('m|message=s'  => 'message',
     'C|check-only' => 'check_only',
     's|sign'	  => 'sign',
     'force',	  => 'force',
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

sub auth {
    eval 'require SVN::Client' or die $@;
    return SVN::Core::auth_open
	([SVN::Client::get_simple_provider (),
	  SVN::Client::get_ssl_server_trust_file_provider (),
	  SVN::Client::get_username_provider ()]);
}

sub under_mirror {
    my ($self, $target) = @_;
    svn_mirror && SVN::Mirror::is_mirrored ($target->{repos}, $target->{path});
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
	('log message', $target_prompt, join ("\n", $msg || '', $target_prompt, ''), 'commit');
}

# Return the editor according to copath, path, and is_mirror (path)
# It will be Editor::XD, repos_commit_editor, or svn::mirror merge back editor.
sub get_editor {
    my ($self, $target) = @_;
    my ($callback, $editor, %cb);

    # XXX: the case that the target is an xd is actually only used in merge.
    if ($target->{copath}) {
	my $xdroot = $target->root ($self->{xd});
	($editor, %cb) = $self->{xd}->get_editor
	    ( %$target,
	      quiet => 1,
	      oldroot => $xdroot,
	      newroot => $xdroot,
	      anchor => $target->{path},
	      target => '',
	      check_only => $self->{check_only});
	return ($editor, %cb);
    }

    my ($base_rev, $m, $mpath);

    if (!$self->{direct} && svn_mirror &&
	(($m, $mpath) = SVN::Mirror::is_mirrored ($target->{repos}, $target->{path}))) {
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
	( SVN::Repos::get_commit_editor
	  ( $target->{repos}, "file://$target->{repospath}",
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

    return ($editor, %cb, mirror => $m, callback => \$callback);
}


sub run {
    my ($self, $target) = @_;

    my $is_mirrored = $self->under_mirror ($target);
    print loc("Commit into mirrored path: merging back directly.\n")
	if $is_mirrored;

    my ($fh, $file);
    my $xdroot = $target->root ($self->{xd});

    unless (defined $self->{message}) {
	($fh, $file) = tmpfile ('commit', UNLINK => 0);
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
	  xdroot => $xdroot,
	  nodelay => 1,
	  delete_verbose => 1,
	  absent_ignore => 1,
	  editor => $statuseditor,
	  cb_conflict => \&SVK::Editor::Status::conflict,
	);

    return loc("no targets to commit\n") if $#{$targets} < 0;

    my $conflicts = grep {$_->[0] eq 'C'} @$targets;
    if ($conflicts) {
	if ($fh) {
	    close $fh;
	    unlink $file;
	}
	return loc("%*(%1,conflict) detected. Use 'svk resolved' after resolving them.\n", $conflicts);
    }


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
    my $fs = $target->{repos}->fs;

    my $committed = sub {
	my ($rev) = @_;
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
	    $self->{xd}{checkout}->store_recursively
		($path, { '.schedule' => undef,
			  '.copyfrom' => undef,
			  '.copyfrom_rev' => undef,
			  '.newprop' => undef,
			  scheduleanchor => undef
			});
	    $self->{xd}{checkout}->store
		($path, { revision => $rev,
			  $action eq 'D' ? ('.deleted' => 1) : (),
			})
		    unless $self->{xd}{checkout}->get ($path)->{revision} == $rev;
	}
	my $root = $fs->revision_root ($rev);
	# update keyword-trnslated files
	for (@$targets) {
	    my ($action, $copath) = @$_;
	    next if $action eq 'D' || -d $copath;
	    my $dpath = $copath;
	    $dpath =~ s|^\Q$target->{copath}\E|$target->{path}|;
	    my $prop = $root->node_proplist ($dpath);
	    my $layer = SVK::XD::get_keyword_layer ($root, $dpath, $prop);
	    my $eol = SVK::XD::get_eol_layer ($root, $dpath, $prop);
	    next unless $layer || ($eol ne ':raw' && $eol ne '');

	    my $fh = SVK::XD::get_fh ($xdroot, '<', $dpath, $copath, 0, $layer, $eol);
	    my $fname = "$copath.svk.old";
	    rename $copath, $fname or die $!;
	    open my ($newfh), ">$eol", $copath or die $!;
	    $layer->via ($newfh) if $layer;
	    slurp_fh ($fh, $newfh);
	    chmod ((stat ($fh))[2], $copath);
	    close $fh;
	    unlink $fname;
	}
    };

    die loc("unexpected error: commit to mirrored path but no mirror object")
	if $is_mirrored && !$self->{direct} && !$cb{mirror};

    ${$cb{callback}} = $committed;

    my %revcache;
    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $xdroot,
	  absent_ignore => 1,
	  editor => $editor,
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
		my $rev = ($xdroot->node_history ($revtarget)->prev (0)->location)[1];
		$revcache{$corev} = $cb{mirror}->find_remote_rev ($rev);
	    }) :
	  ( nodelay => 1 ));
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Commit - Commit changes to depot

=head1 SYNOPSIS

 commit [PATH...]

=head1 OPTIONS

 -m [--message] ARG:    specify commit message ARG
 -s [--sign]:           sign the commit
 -C [--check-only]:     Needs description
 --force:               Needs description
 --direct:              Commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
