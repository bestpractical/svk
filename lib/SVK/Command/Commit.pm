package SVK::Command::Commit;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;
use SVK::CommitStatusEditor;
use SVK::Util qw(get_buffer_from_editor slurp_fh);
use File::Temp;

my $svn_mirror;
eval 'require SVN::Mirror' and ++$svn_mirror;
my $target_prompt = '=== below are targets to be committed ===';

my $auth = SVN::Core::auth_open
    ([SVN::Client::get_simple_provider (),
      SVN::Client::get_ssl_server_trust_file_provider (),
      SVN::Client::get_username_provider ()]);

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

sub target_prompt { $target_prompt }
sub svn_mirror { $svn_mirror }
sub auth { $auth }

sub path_is_mirrored {
    my ($self, $repos, $path) = @_;
    my $fs = $repos->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);

    my $rev = ($root->node_history ($path)->prev (0)->location)[1];

    return (grep {m/^svm:headrev:/} keys %{$fs->revision_proplist ($rev)});
}

# Return the editor according to copath, path, and is_mirror (path)
# It will be XD::Editor, repos_commit_editor, or svn::mirror merge back editor.
sub get_editor {
    my ($self, $target) = @_;
    my ($callback, $editor, %cb);

    if ($target->{copath}) {
	# XXX: really need txn auto cleanup!
	my ($txn, $xdroot) = SVK::XD::create_xd_root ($self->{info}, %$target);

	($editor, %cb) = SVK::XD::get_editor ( $self->{info}, %$target,
					       oldroot => $xdroot,
					       newroot => $xdroot,
					       anchor => $target->{path},
					       target => '',
					       check_only => $self->{check_only});
	return ($editor, %cb, txn => $txn);
    }

    my ($base_rev, $m, $mpath);

    if ($svn_mirror && (($m, $mpath) = SVN::Mirror::is_mirrored ($target->{repos}, $target->{path}))) {
	print "Merge back to SVN::Mirror source $m->{source}.\n";
	if ($self->{check_only}) {
	    print "Check against mirrored directory locally.\n";
	}
	else {
	    $m->{auth} = $auth;
	    ($base_rev, $editor) = $m->get_merge_back_editor
		($mpath, $self->{message},
		 sub { print "Merge back committed as revision $_[0].\n";
		       my $rev = shift;
		       # XXX: some failsafe handler
		       $m->run ($rev);
		       &{$callback} ($m->find_local_rev ($rev), @_)
			   if $callback }
		);
	    $base_rev = $m->{fromrev};
	}
    }

    $editor ||= SVN::Delta::Editor->new
	( SVN::Repos::get_commit_editor
	  ( $target->{repos}, "file://$target->{repospath}",
	    $target->{path}, $ENV{USER}, $self->{message},
	    sub { print "Committed revision $_[0]\n";
		  &{$callback} (@_) if $callback; }
	  ));
    $base_rev ||= $target->{repos}->fs->youngest_rev;

    $editor = SVK::XD::CheckEditor->new ($editor)
	if $self->{check_only};

    my $fs = $target->{repos}->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);

    %cb = ( cb_exist => $self->{cb_exist} ||
	    sub { my $path = $target->{path}.'/'.shift;
		  $root->check_path ($path) != $SVN::Node::none;
	      },
	    cb_rev => sub { $base_rev; },
	    cb_conflict => sub { die "conflict $target->{path}/$_[0]"
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

#    $editor = SVN::Delta::Editor->new (_debug => 1, _editor => [$editor]);

    return ($editor, %cb, mirror => $m, callback => \$callback);

=for comment

    if ($self->{sign} && !$self->{check_only}) {
	my $digest = IO::String->new;
	$cb_closed = sub {
	    print $digest join(' ', 'MD5', $_[1], $_[0])."\n";
	};
	my $old_cb_merged = $cb_merged;
	$cb_merged = sub { my ($editor, $baton, $pool) = @_;
			   my $sig =_sign_gpg ('/tmp/svk-sign',
					       ${$digest->string_ref});
			   $editor->change_dir_prop
			       ($baton, 'svk:signature', $sig);
			   &{$old_cb_merged} (@_) };
    }

=cut

}


sub run {
    my ($self, $target) = @_;

    my $is_mirrored;
    $is_mirrored = $self->path_is_mirrored ($target->{repos}, $target->{path})
	if $svn_mirror;
    print "Commit into mirrored path, merge back directly\n"
	if $is_mirrored;

    my ($txn, $xdroot) = SVK::XD::create_xd_root ($self->{info}, %$target);

    my ($fh, $file);

    unless (defined $self->{message}) {
	($fh, $file) = mkstemps("svk-commitXXXXX", '.tmp');
    }

    print $fh "\n$target_prompt\n" if $fh;

    my $targets = [];
    SVK::XD::checkout_delta ( $self->{info},
			      %$target,
			      baseroot => $xdroot,
			      xdroot => $xdroot,
			      delete_verbose => 1,
			      absent_ignore => 1,
			      strict_add => 1,
			      editor => SVK::CommitStatusEditor->new
			      ( copath => $target->{copath},
				dpath => $target->{path},
				targets => $targets, fh => $fh),
			      cb_conflict => \&SVK::StatusEditor::conflict,
			    );

    if (grep {$_->[0] eq 'C'} @$targets) {
	if ($fh) {
	    close $fh;
	    unlink $fh;
	}
	print "Conflicts detected. Use svk resolved after resolving the conflicts.\n";
	return;
    }

    die "no targets to commit" if $#{$targets} < 0;

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
	for (reverse @$targets) {
	    my $store = ($_->[0] eq 'D' || -d $_->[1]) ?
		'store_recursively' : 'store';
	    $self->{info}->{checkout}->$store ($_->[1], { schedule => undef,
							  newprop => undef,
							  $_->[0] eq 'D' ? (deleted => 1) : (),
							  revision => $rev,
							});
	}
	my $root = $target->{repos}->fs->revision_root ($rev);
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

    die "unexpected error: commit to mirrored path but no mirror object"
	if $is_mirrored && !$cb{mirror};

    ${$cb{callback}} = $committed;

    SVK::XD::checkout_delta ( $self->{info},
			      %$target,
			      baseroot => $xdroot,
			      xdroot => $xdroot,
			      absent_ignore => 1,
			      strict_add => 1,
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
					($self->{info}->{checkout}->get($cotarget)->{revision});
				    $fs->revision_prop ($root->node_created_rev ($revtarget),
							"svm:headrev:$cb{mirror}{source}");
				}) : (),
			    );
    $txn->abort if $txn;

    return;
}

1;
