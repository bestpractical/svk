package SVK::Editor::Merge;
use strict;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVN::Delta::Editor);
use SVK::Notify;
use SVK::I18N;
use SVK::Util qw( slurp_fh md5_fh get_anchor tmpfile devnull );
use IO::Digest;

=head1 NAME

SVK::Editor::Merge - An editor that does merges for the storage editor

=head1 SYNOPSIS

  $editor = SVK::Editor::Merge->new
    ( anchor => $anchor,
      base_anchor => $base_anchor,
      base_root => $fs->revision_root ($arg{fromrev}),
      target => $target,
      storage => $storage_editor,
      %cb,
    );


=head1 DESCRIPTION

Given the base root and callbacks for local tree, SVK::Editor::Merge
forwards the incoming editor calls to the storage editor for modifying
the local tree, and merges the tree delta and text delta
transparently.

=head1 PARAMETERS

=head2 options for base and target tree

=over

=item anchor

The anchor of the target tree.

=item target

The target path component of the target tree.

=item base_anchor

The anchor of the base tree.

=item base_root

The root object of the base tree.

=item external

External tool that would be called upon textual conflicts.

=item storage

The editor that will receive the merged callbacks.

=item allow_conflicts

Close the edito instead of abort when there are conflicts.

=item open_nonexist

open the directory even if cb_exist failed. This is for use in
conjunction with L<SVK::Editor::Rename> for the case that a descendent
exists but its parent does not.

=back

=head2 callbacks for local tree

Since the merger needs to have information about the local tree, some
callbacks must be supplied.

=over

=item cb_exist

Check if the given path exists.

=item cb_rev

Check the revision of the given path.

=item cb_conflict

Called when a conflict is detected.

=item cb_localmod

Called when the merger needs to retrieve the local modification of a
file. Return an arrayref of filename, filehandle, and md5. Return
undef if there is no local modification.

=item cb_dirdelta

When C<delete_entry> needs to check if everything to be deleted does
not cause conflict on the directory, it calls the callback with path,
base_root, and base_path. The returned value should be a hash with
changed paths being the keys and change types being the values.

=item cb_merged

Called right before closing the top directory with storage editor,
root baton, and pool.

=item cb_closed

Called after each file close call.

=back

=cut

use Digest::MD5 qw(md5_hex);
use File::Compare ();

sub cb_for_root {
    my ($root, $anchor, $base_rev) = @_;
    return ( cb_exist =>
	     sub { my $path = $anchor.'/'.shift;
		   $root->check_path ($path) != $SVN::Node::none;
	       },
	     cb_rev => sub { $base_rev; },
	     cb_localmod =>
	     sub { my ($path, $checksum, $pool) = @_;
		   $path = "$anchor/$path";
		   my $md5 = $root->file_md5_checksum ($path, $pool);
		   return if $md5 eq $checksum;
		   return [$root->file_contents ($path, $pool),
			   undef, $md5];
	       },
	     cb_dirdelta =>
	     sub { my ($path, $base_root, $base_path, $pool) = @_;
		   my $modified;
		   my $editor =  SVK::Editor::Status->new
		       ( notify => SVK::Notify->new
			 ( cb_flush => sub {
			       my ($path, $status) = @_;
			       $modified->{$path} = $status->[0];
			   }));
		   SVK::XD->depot_delta (oldroot => $base_root, newroot => $root,
					 oldpath => [$base_path, ''],
					 newpath => "$anchor/$path",
					 editor => $editor,
					 no_textdelta => 1, no_recurse => 1);
		   return $modified;
	       },
	   );
}

# translate the path before passing to cb_*
sub cb_translate {
    my ($cb, $translate) = @_;
    for (qw/cb_exist cb_rev cb_conflict cb_localmod cb_dirdelta/) {
	my $sub = $cb->{$_};
	next unless $sub;
	$cb->{$_} = sub { my $path = shift; $translate->($path);
			  $sub->($path, @_)};
    }
}

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
    $self->{storage}->set_target_revision ($revision);
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{baserev} = $baserev;
    $self->{notify} ||= SVK::Notify->new_with_report ($self->{report}, $self->{target});
    $self->{storage_baton}{''} =
	$self->{storage}->open_root ($self->{cb_rev}->($self->{target}||''));
    $self->{notify}->node_status ('', '');
    return '';
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    return unless defined $pdir;
    ++$self->{changes};
    if (!$self->{added}{$pdir} && $self->{cb_exist}->($path)) {
	$self->{info}{$path}{addmerge} = 1;
	$self->{info}{$path}{open} = [$pdir, -1];
	$self->{info}{$path}{fpool} = pop @arg;
	return $path;
    }
    else {
	$self->{notify}->node_status ($path, 'A');
	$self->{storage_baton}{$path} =
	    $self->{storage}->add_file ($path, $self->{storage_baton}{$pdir}, @arg);
	return $path;
    }
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    # modified but rm locally - tag for conflict?
    if ($self->{cb_exist}->($path)) {
	$self->{info}{$path}{open} = [$pdir, $rev];
	$self->{info}{$path}{fpool} = $pool;
	$self->{notify}->node_status ($path, '');
	return $path;
    }
    ++$self->{skipped};
    $self->{notify}->flush ($path);
    return undef;
}

sub ensure_open {
    my ($self, $path) = @_;
    return unless $self->{info}{$path}{open};
    my ($pdir, $rev, $pool) = (@{$self->{info}{$path}{open}},
			       $self->{info}{$path}{fpool});
    $self->{storage_baton}{$path} ||=
	$self->{storage}->open_file ($path, $self->{storage_baton}{$pdir},
				     $self->{cb_rev}->($path), $pool);
    ++$self->{changes};
    delete $self->{info}{$path}{open};
}

sub ensure_close {
    my ($self, $path, $checksum, $pool) = @_;

    $self->cleanup_fh ($self->{info}{$path}{fh});
    $self->{notify}->flush ($path, 1);
    $self->{cb_closed}->($path, $checksum, $pool)
        if $self->{cb_closed};

    if (my $baton = $self->{storage_baton}{$path}) {
	$self->{storage}->close_file ($baton, $checksum, $pool);
	delete $self->{storage_baton}{$path};
    }

    delete $self->{info}{$path};
}

sub node_conflict {
    my ($self, $path) = @_;
    $self->{cb_conflict}->($path) if $self->{cb_conflict};
    ++$self->{conflicts};
    $self->{notify}->node_status ($path, 'C');
}

sub cleanup_fh {
    my ($self, $fh) = @_;
    for (qw/base new local/) {
	close $fh->{$_}[0]
	    if $fh->{$_}[0];
    }
}

sub prepare_fh {
    my ($self, $fh) = @_;
    # XXX: need to respect eol-style here?
    for my $name (qw/base new local/) {
	my $entry = $fh->{$name};
	next unless $entry->[0];
	next if $entry->[1];
	my $tmp = [tmpfile("$name-"), $entry->[2]];
	slurp_fh ($entry->[0], $tmp->[0]);
	close $entry->[0];
	$entry = $fh->{$name} = $tmp;
	seek $entry->[0], 0, 0;
    }
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $path;

    my $info = $self->{info}{$path};
    my $fh = $info->{fh} = {};
    $pool->default if $pool && $pool->can ('default');
    my ($base);
    if (($pool = $info->{fpool}) &&
	($fh->{local} = $self->{cb_localmod}->($path, $checksum || '', $pool))) {
	# retrieve base
	unless ($info->{addmerge}) {
	    $fh->{base} = [tmpfile('base-')];
	    $path = "$self->{base_anchor}/$path" if $self->{base_anchor};
	    slurp_fh ($self->{base_root}->file_contents ($path, $pool),
		      $fh->{base}[0]);
	    $base = $fh->{base}[0];
	    seek $base, 0, 0;
	}
	# get new
	$fh->{new} = [tmpfile('new-')];
	return [SVN::TxDelta::apply ($base, $fh->{new}[0], undef, undef, $pool)];
    }
    $self->{notify}->node_status ($path, 'U')
	unless $self->{notify}->node_status ($path);

    $self->ensure_open ($path);
    return $self->{storage}->apply_textdelta ($self->{storage_baton}{$path},
					      $checksum, $pool);
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $path;
    $pool->default if $pool && $pool->can ('default');
    my $info = $self->{info}{$path};
    my $fh = $info->{fh};
    my $iod;

    no warnings 'uninitialized';
    # let close_directory reports about its children
    if ($info->{fh}{new}) {
	$self->prepare_fh ($fh);

	if ($checksum eq $fh->{local}[2] ||
	    # XXX: mark this as a change too?
	    File::Compare::compare ($fh->{new}[1], $fh->{local}[1]) == 0) {
	    $self->{notify}->node_status ($path, 'g');
	    $self->ensure_close ($path, $checksum, $pool);
	    return;
	}

	$self->ensure_open ($path);
	$fh->{base}[1] = devnull if $info->{addmerge};
	my $diff = SVN::Core::diff_file_diff3
	    (map {$fh->{$_}[1]} qw/base local new/);
	my $mfh = tmpfile ('merged-');
	SVN::Core::diff_file_output_merge
		( $mfh, $diff,
		  (map {
		      $fh->{$_}[1]
		  } qw/base local new/),
		  "||||||| base",
		  "<<<<<<< local",
		  ">>>>>>> new",
		  "=======",
		  1, 0, $pool);

	my $conflict = SVN::Core::diff_contains_conflicts ($diff);
	my $mfn;
	if ($conflict && $self->{external}) {
	    $mfn = tmpfile ('merged-', OPEN => 0);
	    # maybe some message here
	    print "Invoking external merge tool for $path.\n";
	    system (split (' ', $self->{external}),
		    "$path (YOURS)", $fh->{local}[1],
		    "$path (BASE)", $fh->{base}[1],
		    "$path (THEIRS)", $fh->{new}[1],
		    $mfn
		    );
	    if (-e $mfn) {
		open $mfh, '<:raw', $mfn or die $!;
		$conflict = 0;
	    }
	    else {
		print "$path not merged.\n"
	    }
	}

	$self->{notify}->node_status ($path, $conflict ? 'C' : 'G');
	seek $mfh, 0, 0;
	$iod = IO::Digest->new ($mfh, 'MD5');

	my $handle = $self->{storage}->
	    apply_textdelta ($self->{storage_baton}{$path}, $fh->{local}[2],
			     $pool);

	if ($handle && $#{$handle} >= 0) {
	    if ($self->{send_fulltext}) {
		SVN::TxDelta::send_stream ($mfh, @$handle, $pool)
			if $handle && $#{$handle} >= 0;
	    }
	    else {
		seek $fh->{local}[0], 0, 0;
		my $txstream = SVN::TxDelta::new
		    ($fh->{local}[0], $mfh, $pool);
		SVN::TxDelta::send_txstream ($txstream, @$handle, $pool)
	    }
	}

	close $mfh;
	unlink $mfn if $mfn;
	undef $fh->{base}[1] if $info->{addmerge};
	$self->cleanup_fh ($fh);

	$self->node_conflict ($path) if $conflict;
    }
    elsif ($info->{fpool} && !$self->{notify}->node_status ($path)) {
	# open but prop edit only, load local checksum
	if (my $local = $self->{cb_localmod}->($path, $checksum, $pool)) {
	    $checksum = $local->[2];
	    close $local->[0];
	}
    }

    $self->{notify}->flush ($path, 1);
    $self->{cb_merged}->($self->{storage}, $self->{storage_baton}{$path}, $pool)
	if $path eq $self->{target} && $self->{changes} && $self->{cb_merged};
    $checksum = $iod->hexdigest if $iod;
    $self->ensure_close ($path, $checksum, $pool);
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    return undef unless defined $pdir;
    if (!$self->{added}{$pdir} && $self->{cb_exist}->($path)) {
	$self->{notify}->flush ($path) ;
	return undef;
    }
    $self->{added}{$path} = 1;
    $self->{storage_baton}{$path} =
	$self->{storage}->add_directory ($path, $self->{storage_baton}{$pdir},
					 @arg);
    $self->{notify}->node_status ($path, 'A');
    $self->{notify}->flush ($path, 1);
    ++$self->{changes};
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, @arg) = @_;
    unless ($self->{open_nonexist}) {
	return undef unless defined $pdir;
	unless ($self->{cb_exist}->($path) || $self->{open_nonexist}) {
	    $self->{notify}->flush ($path);
	    return undef;
	}
    }
    $self->{notify}->node_status ($path, '');
    $self->{storage_baton}{$path} =
	$self->{storage}->open_directory ($path, $self->{storage_baton}{$pdir},
					  $self->{cb_rev}->($path), @arg);
    return $path;
}

sub close_directory {
    my ($self, $path, $pool) = @_;
    return unless defined $path;
    no warnings 'uninitialized';

    delete $self->{added}{$path};
    $self->{notify}->flush_dir ($path);

    my $baton = $self->{storage_baton}{$path};
    $self->{cb_merged}->($self->{storage}, $baton, $pool)
	if $path eq $self->{target} && $self->{changes} && $self->{cb_merged};

    $self->{storage}->close_directory ($baton, $pool);
    delete $self->{storage_baton}{$path}
	unless $path eq '';
}

# returns undef for deleting this, a hash for partial delete.
# returns 1 for merged delete
# Note that empty hash means don't delete.
sub _check_delete_conflict {
    my ($self, $path, $rpath, $kind, $pdir, $pool) = @_;
    return $self->{cb_localmod}->
	($path, $self->{base_root}->file_md5_checksum ($rpath, $pool), $pool)
	    ? {} : undef
		if $kind == $SVN::Node::file;

    my $dirmodified = $self->{cb_dirdelta}->($path, $self->{base_root}, $rpath);
    my $entries = $self->{base_root}->dir_entries ($rpath);
    my ($torm, $modified, $merged);
    for my $name (sort keys %$entries) {
	my ($cpath, $crpath) = ("$path/$name", "$rpath/$name");
	if (my $mod = $dirmodified->{$name}) {
	    if ($mod eq 'D') {
		$self->{notify}->node_status ($cpath, 'd');
		++$merged;
	    }
	    else {
		++$modified;
		$self->node_conflict ($cpath);
	    }
	    delete $dirmodified->{$name};
	}
	else { # dir or unmodified file
	    my $entry = $entries->{$name};
	    $torm->{$name} = undef, next
		if $entry->kind == $SVN::Node::file;

	    if ($self->{cb_exist}->($cpath)) {
		$torm->{$name} = $self->_check_delete_conflict
		    ($cpath, $crpath, $SVN::Node::dir, $pdir, $pool);
		if (ref ($torm->{$name})) {
		    $self->node_conflict ($cpath);
		    ++$modified;
		}
		if ($torm->{$name} && $torm->{$name} == 1) {
		    ++$merged;
		}
	    }
	    else {
		$torm->{$name} = 1;
		++$merged;
	    }
	}
    }
    for my $name (keys %$dirmodified) {
	my ($cpath, $crpath) = ("$path/$name", "$rpath/$name");
	++$modified;
	$self->node_conflict ($cpath);
    }
    if ($modified || $merged) {
	# maybe leave the status to _partial delete?
	$self->{notify}->node_status ("$path/$_", defined $torm->{$_} ? 'd' : 'D')
	    for grep {!ref($torm->{$_})} keys %$torm;
    }
    return $torm if $modified;
    return $merged ? 1 : undef;
}

sub _partial_delete {
    my ($self, $torm, $path, $pbaton, $pool) = @_;
    my $baton = $self->{storage}->open_directory ($path, $pbaton,
						  $self->{cb_rev}->($path), $pool);
    for (sort keys %$torm) {
	my $cpath = "$path/$_";
	if (ref $torm->{$_}) {
	    $self->_partial_delete ($torm->{$_}, $cpath, $baton,
				    SVN::Pool->new ($pool));
	}
	elsif ($self->{cb_exist}->($cpath)) {
	    $self->{storage}->delete_entry ($cpath, $self->{cb_rev}->($cpath),
					    $baton, $pool);
	}
    }
    $self->{storage}->close_directory ($baton, $pool);
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
    no warnings 'uninitialized';
    return unless defined $pdir && $self->{cb_exist}->($path);

    my $rpath = $self->{base_anchor} eq '/' ? "/$path" : "$self->{base_anchor}/$path";
    my $torm = $self->_check_delete_conflict ($path, $rpath,
					      $self->{base_root}->check_path ($rpath), $pdir, @arg);

    if ($torm) {
	$self->node_conflict ($path);
	$self->_partial_delete ($torm, $path, $self->{storage_baton}{$pdir}, @arg);
    }
    else {
	$self->{storage}->delete_entry ($path, $self->{cb_rev}->($path),
					$self->{storage_baton}{$pdir}, @arg);
	$self->{notify}->node_status ($path, 'D');
    }
    ++$self->{changes};
}

sub change_file_prop {
    my ($self, $path, @arg) = @_;
    return unless $path;
    $self->ensure_open ($path);
    $self->{storage}->change_file_prop ($self->{storage_baton}{$path}, @arg);
    $self->{notify}->prop_status ($path, 'U');
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
    # XXX: need the status-fu like files to track removed / renamed
    # directories
    # return unless $self->{info}{$path}{status};

    # there should be a magic flag indicating if svk:merge prop should
    # be dealt.
    return if $arg[0] eq 'svk:merge';
    return if $arg[0] =~ m/^svm:/;
    $path = '' unless defined $path;
    $self->{storage}->change_dir_prop ($self->{storage_baton}{$path}, @arg);
    $self->{notify}->prop_status ($path, 'U');
    ++$self->{changes};
}

sub close_edit {
    my ($self, @arg) = @_;
    if ($self->{allow_conflicts} ||
	(defined $self->{storage_baton}{''} && !$self->{conflicts}) && $self->{changes}) {
	$self->{storage}->close_edit(@arg);
    }
    else {
	print loc("Empty merge.\n");
	$self->{storage}->abort_edit(@arg);
    }
}

=head1 BUGS

=over

=item Tree merge

still very primitive, have to handle lots of cases

=back

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
