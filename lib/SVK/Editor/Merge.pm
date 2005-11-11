package SVK::Editor::Merge;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use SVK::Inspector::Root;

require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);
use SVK::I18N;
use autouse 'SVK::Util'
    => qw( slurp_fh md5_fh tmpfile devnull abs2rel );

use constant FH => 0;
use constant FILENAME => 1;
use constant CHECKSUM => 2;

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

=item cb_localprop

Called when the merger needs to retrieve the local modification of a
property. Return the property value.

=item cb_prop_merged

Called when properties are merged without changes, that is, the C<g>
status.

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
    my ($class, $root, $anchor, $base_rev) = @_;
    # XXX $root and $anchor are actually SVK::Path
    my $inspector = SVK::Inspector::Root->new({
        root => $root, 
        anchor => $anchor, 
    });

    return (
        inspector => $inspector,
        cb_rev => sub { $base_rev },
        $inspector->compat_cb
    );
}

# translate the path before passing to cb_*
sub cb_translate {
    my ($cb, $translate) = @_;
    $cb->{inspector}->push_translation($translate);
    for (qw/cb_conflict/) {
        my $sub = $cb->{$_};
        next unless $sub;
        $cb->{$_} = sub { my $path = shift; $translate->($path);
                  unshift @_, $path; goto &$sub };
    }
}

sub copy_info {
    my ($self, $src_from, $src_fromrev, $dst_from, $dst_fromrev) = @_;
    $self->{copy_info}{$src_from}{$src_fromrev} = [$dst_from, $dst_fromrev];
}

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
    $self->{storage}->set_target_revision ($revision);
}

sub inspector {
    my $self = shift;
    return $self->{inspector};
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{baserev} = $baserev;
    $self->{notify} ||= SVK::Notify->new_with_report ($self->{report}, $self->{target});
    $self->{storage_baton}{''} =
	$self->{storage}->open_root ($self->{cb_rev}->($self->{target}||''));
    $self->{notify}->node_status ('', '');

    my $ticket = $self->{ticket};
    $self->{dh} = Data::Hierarchy->new;
    $self->{cb_merged} =
	sub { my ($editor, $baton, $type, $pool) = @_;
	      my $func = "change_${type}_prop";
	      $editor->$func ($baton, 'svk:merge', $ticket->(), $pool);
	  } if $ticket;

    return '';
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    return unless defined $pdir;
    my $pool = pop @arg;
    # a replaced node shouldn't be checked with cb_exist
    my $touched = $self->{notify}->node_status($path);
    if (!$self->{added}{$pdir} && !$touched &&
	(my $kind = $self->inspector->exist($path, $pool))) {
	unless ($kind == $SVN::Node::file) {
	    $self->{notify}->flush ($path) ;
	    return undef;
	}
	$self->{info}{$path}{addmerge} = 1;
	$self->{info}{$path}{open} = [$pdir, -1];
	$self->{info}{$path}{fpool} = $pool;
    }
    else {
	++$self->{changes};
	$self->{added}{$path} = 1;
	$self->{notify}->node_status ($path, $touched ? 'R' : 'A');
	if (defined $arg[0]) {
	    $self->{notify}->hist_status ($path, '+');
	    @arg = $self->resolve_copy($path, @arg);
	    $self->{info}{$path}{baseinfo} = [$self->_resolve_base($path)];
	    $self->{info}{$path}{fpool} = $pool;
	}
	$self->{storage_baton}{$path} =
	    $self->{storage}->add_file ($path, $self->{storage_baton}{$pdir}, @arg, $pool);
	$pool->default if $pool && $pool->can ('default');
	# XXX: fpool is used for testing if the file is open rather than add,
	# so use another field to hold it.
	$self->{info}{$path}{hold_pool} = $pool;
    }
    return $path;
}

sub _resolve_base {
    my ($self, $path, $orig) = @_;
    my ($entry) = $self->{dh}->get("/$path");
    return unless $entry->{copyanchor};
    $entry = $self->{dh}->get($entry->{copyanchor})
	unless $entry->{copyanchor} eq "/$path";
    my $key = $orig ? 'orig_copyfrom' : 'copyfrom';
    return (abs2rel("/$path",
		    $entry->{copyanchor} => $entry->{".$key"}, '/'),
	    $entry->{".${key}_rev"});
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    # modified but rm locally - tag for conflict?
    my ($basepath, $fromrev) = $self->_resolve_base($path);
    $basepath = $path unless defined $basepath;
    if ($self->inspector->exist($basepath, $pool)) {
	$self->{info}{$path}{baseinfo} = [$basepath, $fromrev]
	    if defined $fromrev;
	$self->{info}{$path}{open} = [$pdir, $rev];
	$self->{info}{$path}{fpool} = $pool;
	$self->{notify}->node_status ($path, '');
	$pool->default if $pool && $pool->can ('default');
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

    if ($path eq $self->{target} && $self->{changes} && $self->{cb_merged}) {
	$self->ensure_open ($path);
	$self->{cb_merged}->($self->{storage}, $self->{storage_baton}{$path}, 'file', $pool);
    }

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
	close $fh->{$_}[FH]
	    if $fh->{$_}[FH];
    }
}

sub prepare_fh {
    my ($self, $fh, $eol) = @_;
    for my $name (qw/base new local/) {
	my $entry = $fh->{$name};
	next unless $entry->[FH];
	# if there's eol translation required, we can't use the
	# prepared tmp files.
	if ($entry->[FILENAME]) {
	    next unless $eol;
	    # reopen the tmp file, since apply_textdelta closes it
	    open $entry->[FH], $entry->[FILENAME];
	}
	my $tmp = [tmpfile("$name-"), $entry->[CHECKSUM]];
	binmode $tmp->[FH], $eol if $eol;
	slurp_fh ($entry->[FH], $tmp->[FH]);
	close $entry->[FH];
	$entry = $fh->{$name} = $tmp;
	seek $entry->[FH], 0, 0;
    }
}

sub _retrieve_base
{
    my ($self, $path, $pool) = @_;
    my @base = tmpfile('base-');

    my ($basepath, $fromrev) = $self->{info}{$path}{baseinfo} ?
	$self->_resolve_base($path, 1)
      : ($path);
    my $root = $fromrev ? $self->{base_root}->fs->revision_root($fromrev, $pool)
	: $self->{base_root};
    $basepath = "$self->{base_anchor}/$path"
	if $basepath !~ m{^/} && $self->{base_anchor};
    slurp_fh ($root->file_contents ($basepath, $pool), $base[FH]);
    seek $base[FH], 0, 0;
    return @base;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $path;

    my $info = $self->{info}{$path};
    my ($basepath, $fromrev) = $info->{baseinfo} ? @{$info->{baseinfo}} : ($path);
    my $fh = $info->{fh} = {};
    if (($pool = $info->{fpool}) &&
	($fh->{local} = $self->{cb_localmod}->($basepath, $checksum || '', $pool))) {
	# retrieve base
	unless ($info->{addmerge}) {
	    $fh->{base} = [$self->_retrieve_base($path, $pool)];
	}
	# get new
	$fh->{new} = [tmpfile('new-')];
	return [SVN::TxDelta::apply ($fh->{base}[FH], $fh->{new}[FH], undef, undef, $pool)];
    }
    $self->{notify}->node_status ($path, 'U')
	unless $self->{notify}->node_status ($path);

    $self->ensure_open ($path);

    my $handle = $self->{storage}->apply_textdelta ($self->{storage_baton}{$path},
						    $checksum, $pool);

    if ($self->{storage_has_unwritable} && !$handle) {
	delete $self->{notify}{status}{$path};
	$self->{notify}->flush ($path);
    }
    return $handle;
}

sub _merge_text_change {
    my ($self, $fh, $label, $pool) = @_;
    my $diff = SVN::Core::diff_file_diff3
	(map {$fh->{$_}[FILENAME]} qw/base local new/);
    my $mfh = tmpfile ('merged-');
    my $marker = time.int(rand(100000));
    SVN::Core::diff_file_output_merge
	    ( $mfh, $diff,
	      (map {
		  $fh->{$_}[FILENAME]
	      } qw/base local new/),
	      "==== ORIGINAL VERSION $label $marker",
	      ">>>> YOUR VERSION $label $marker",
	      "<<<< $marker",
	      "==== THEIR VERSION $label $marker",
	      1, 0, $pool);

    my $conflict = SVN::Core::diff_contains_conflicts ($diff);
    if (my $resolve = $self->{resolve}) {
	$resolve->run
	    ( fh              => $fh,
	      mfh             => $mfh,
	      path            => $label,
	      marker          => $marker,
	      # Do not run resolve for diffs with no conflicts
	      ($conflict ? (has_conflict => 1) : ()),
            );
	$conflict = 0 if $resolve->{merged};
	my $mfn = $resolve->{merged} || $resolve->{conflict};
	open $mfh, '<:raw', $mfn or die "Cannot read $mfn: $!" if $mfn;
    }
    seek $mfh, 0, 0; # for skipped
    return ($conflict, $mfh);
}

sub _overwrite_local_file {
    my ($self, $fh, $path, $nfh, $pool) = @_;
    # XXX: document why this is like this
    my $storagebase = $fh->{local};
    my $info = $self->{info}{$path};
    my ($basepath, $fromrev) = $info->{baseinfo} ? @{$info->{baseinfo}} : ($path);

    if ($fromrev) {
	my $sbroot = $self->{base_root}->fs->revision_root($fromrev, $pool);
	$storagebase->[FH] = $sbroot->file_contents($basepath, $pool);
	$storagebase->[CHECKSUM] = $sbroot->file_md5_checksum($basepath, $pool);
    }

    my $handle = $self->{storage}->
	apply_textdelta ($self->{storage_baton}{$path},
			 $storagebase->[CHECKSUM], $pool);

    if ($handle && $#{$handle} >= 0) {
	if ($self->{send_fulltext}) {
	    SVN::TxDelta::send_stream ($nfh, @$handle, $pool);
	}
	else {
	    seek $storagebase->[FH], 0, 0 unless $fromrev; # don't seek for sb
	    my $txstream = SVN::TxDelta::new($fh->{local}[FH], $nfh, $pool);
	    SVN::TxDelta::send_txstream ($txstream, @$handle, $pool);
	}
	return 1;
    }

    if ($self->{storage_has_unwritable}) {
	delete $self->{notify}{status}{$path};
	$self->{notify}->flush ($path);
	return 0;
    }
    return 1;
}

sub _merge_file_unchanged {
    my ($self, $path, $checksum, $pool) = @_;
    ++$self->{changes} unless $self->{g_merge_no_a_change};
    $self->{notify}->node_status ($path, 'g');
    $self->ensure_close ($path, $checksum, $pool);
    return;
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $path;
    my $info = $self->{info}{$path};
    my $fh = $info->{fh};
    my $iod;

    my ($basepath, $fromrev) = $info->{baseinfo} ? @{$info->{baseinfo}} : ($path);
    no warnings 'uninitialized';
    my $storagebase_checksum = $fh->{local}[CHECKSUM];
    if ($fromrev) {
	$storagebase_checksum = $self->{base_root}->fs->revision_root
	    ($fromrev, $pool)->file_md5_checksum($basepath, $pool);
    }

    # let close_directory reports about its children
    if ($info->{fh}{new}) {

	$self->_merge_file_unchanged ($path, $checksum, $pool), return
	    if $checksum eq $storagebase_checksum;

	my $eol = $self->{cb_localprop}->($basepath, 'svn:eol-style', $pool);
	my $eol_layer = SVK::XD::get_eol_layer({'svn:eol-style' => $eol}, '>');
	$eol_layer = '' if $eol_layer eq ':raw';
	$self->prepare_fh ($fh, $eol_layer);
	# XXX: There used be a case that this explicit comparison is
	# needed, but i'm not sure anymore.
	$self->_merge_file_unchanged ($path, $checksum, $pool), return
	    if File::Compare::compare ($fh->{new}[FILENAME], $fh->{local}->[FILENAME]) == 0;

	$self->ensure_open ($path);
        if ($info->{addmerge}) {
            $fh->{base}[FILENAME] = devnull;
            open $fh->{base}[FH], '<', $fh->{base}[FILENAME];
        }
	my ($conflict, $mfh) = $self->_merge_text_change ($fh, $path, $pool);
	$self->{notify}->node_status ($path, $conflict ? 'C' : 'G');

	$eol_layer = SVK::XD::get_eol_layer({'svn:eol-style' => $eol}, '<');
	binmode $mfh, $eol_layer or die $! if $eol_layer;

	$iod = IO::Digest->new ($mfh, 'MD5');

	if ($self->_overwrite_local_file ($fh, $path, $mfh, $pool)) {
	    undef $fh->{base}[FILENAME] if $info->{addmerge};
	    $self->node_conflict ($path) if $conflict;
	}
	$self->cleanup_fh ($fh);
    }
    elsif ($info->{fpool}) {
	if (!$self->{notify}->node_status($path) || !exists $fh->{local} ) {
	    # open but without text edit, load local checksum
	    if ($basepath ne $path) {
		$checksum = $self->{base_root}->fs->revision_root($fromrev, $pool)->file_md5_checksum($basepath, $pool);
	    }
	    elsif (my $local = $self->{cb_localmod}->($basepath, $checksum, $pool)) {
		$checksum = $local->[CHECKSUM];
		close $local->[FH];
	    }
	}
    }

    $checksum = $iod->hexdigest if $iod;
    $self->ensure_close ($path, $checksum, $pool);
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    return undef unless defined $pdir;
    my $pool = pop @arg;
    my $touched = $self->{notify}->node_status($path);
    undef $touched if $touched && $touched eq 'C';
    # Don't bother calling cb_exist (which might be expensive if the parent is
    # already added.
    if (!$self->{added}{$pdir} && !$touched &&
	(my $kind = $self->inspector->exist($path, $pool))) {
	unless ($kind == $SVN::Node::dir) {
	    $self->{notify}->flush ($path) ;
	    return undef;
	}
	$self->{storage_baton}{$path} =
	    $self->{storage}->open_directory ($path, $self->{storage_baton}{$pdir},
					      $self->{cb_rev}->($path), $pool);
	$self->{notify}->node_status ($path, 'G');
    }
    else {
	if (defined $arg[0]) {
	    @arg = $self->resolve_copy($path, @arg);
	}
	my $baton =
	    $self->{storage}->add_directory ($path, $self->{storage_baton}{$pdir},
					     @arg, $pool);
	unless (defined $baton) {
	    $self->{notify}->flush ($path);
	    return undef;
	}
	$self->{storage_baton}{$path} = $baton;
	$self->{added}{$path} = 1;
	$self->{notify}->hist_status ($path, '+')
	    if defined $arg[0];
	$self->{notify}->node_status ($path, $touched ? 'R' : 'A');
	$self->{notify}->flush ($path, 1);
    }
    ++$self->{changes};
    return $path;
}

sub resolve_copy {
    my ($self, $path, $from, $rev) = @_;
    die "unknown copy $from $rev for $path"
	unless exists $self->{copy_info}{$from}{$rev};
    my ($dstfrom, $dstrev) = @{$self->{copy_info}{$from}{$rev}};
    $self->{dh}->store("/$path", { copyanchor => "/$path",
				   '.copyfrom' => $dstfrom,
				   '.copyfrom_rev' => $dstrev,
				   '.orig_copyfrom' => $from,
				   '.orig_copyfrom_rev' => $rev,
				 });
    return $self->{cb_copyfrom}->($dstfrom, $dstrev)
	if $self->{cb_copyfrom};
    return ($dstfrom, $dstrev);
}

sub open_directory {
    my ($self, $path, $pdir, $rev, @arg) = @_;
    my $pool = $arg[-1];

    unless ($self->{open_nonexist}) {
	return undef unless defined $pdir;

	my ($basepath, $fromrev) = $self->_resolve_base($path);
	$basepath = $path unless defined $basepath;

	unless ($self->inspector->exist($basepath, $pool) || $self->{open_nonexist}) {
	    ++$self->{skipped};
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
    $self->{cb_merged}->($self->{storage}, $baton, 'dir', $pool)
	if $path eq $self->{target} && $self->{changes} && $self->{cb_merged};

    $self->{storage}->close_directory ($baton, $pool);
    delete $self->{storage_baton}{$path}
	unless $path eq '';
}

sub _merge_file_delete {
    my ($self, $path, $rpath, $pdir, $pool) = @_;
    my ($basepath, $fromrev) = $self->_resolve_base($path);
    $basepath = $path unless defined $basepath;

    return undef unless $self->{cb_localmod}->(
		$basepath,
		$self->{base_root}->file_md5_checksum ($rpath, $pool),
		$pool);
    return {} unless $self->{resolve};

    my $fh = $self->{info}{$path}->{fh} || {};
    $fh->{base} ||= [$self->_retrieve_base($path, $pool)];
    $fh->{new} = [tmpfile('new-')];
    $fh->{local} = [tmpfile('local-')];
    my ($tmp) = $self->{cb_localmod}->($basepath, '', $pool);
    slurp_fh ( $tmp->[FH], $fh->{local}[FH]);
    seek $fh->{local}[FH], 0, 0;
    $fh->{local}[CHECKSUM] = $tmp->[CHECKSUM];

    my ($conflict, $mfh) = $self->_merge_text_change( $fh, $path, $pool);
    if( $conflict ) {
	$self->clean_up($fh);
	return {};
    } elsif( !(stat($mfh))[7] ) {
	#delete file if merged size is 0
	$self->clean_up($fh);
	return undef;
    }
    seek $mfh, 0, 0;
    my $iod = IO::Digest->new ($mfh, 'MD5');

    $self->{info}{$path}{open} = [$pdir, -1];
    $self->{info}{$path}{fpool} = $pool;
    $self->ensure_open ($path);
    $self->_overwrite_local_file ($fh, $path, $mfh, $pool);
    ++$self->{changes};
    $self->ensure_close ($path, $iod->hexdigest, $pool);

    return 1;
}
# returns undef for deleting this, a hash for partial delete.
# returns 1 for merged delete
# Note that empty hash means don't delete.
sub _check_delete_conflict {
    my ($self, $path, $rpath, $kind, $pdir, $pool) = @_;

    return $self->_merge_file_delete($path, $rpath, $pdir, $pool) if $kind == $SVN::Node::file;

    my ($basepath, $fromrev) = $self->_resolve_base($path, 1);
    $basepath = $path unless defined $basepath;
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

	    if ($self->inspector->exist($cpath, $pool)) {
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
	elsif ($self->inspector->exist($cpath, $pool)) {
	    $self->{storage}->delete_entry ($cpath, $self->{cb_rev}->($cpath),
					    $baton, $pool);
	}
    }
    $self->{storage}->close_directory ($baton, $pool);
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
    no warnings 'uninitialized';
    my $pool = $arg[-1];
    my ($basepath, $fromrev) = $self->_resolve_base($path);
    $basepath = $path unless defined $basepath;

    return unless defined $pdir && $self->inspector->exist($basepath, $pool);
    my $rpath = $basepath =~ m{^/} ? $basepath :
	$self->{base_anchor} eq '/' ? "/$basepath" : "$self->{base_anchor}/$basepath";
    my $torm;
    # XXX: need txn-aware cb_*! for the case current path is from a
    # copy and to be deleted
    if ($self->inspector->exist($path, $pool)) {
	# XXX: this is evil
	local $self->{base_root} = $self->{base_root}->fs->revision_root($fromrev) if $basepath ne $path;
	$torm = $self->_check_delete_conflict ($path, $rpath,
					      $self->{base_root}->check_path ($rpath), $pdir, @arg);
    }

    if (ref($torm)) {
	$self->node_conflict ($path);
	$self->_partial_delete ($torm, $path, $self->{storage_baton}{$pdir}, @arg);
    } elsif( $torm && $torm == 1) {
	$self->{notify}->node_status ($path, 'G');
    } else {
	$self->{storage}->delete_entry ($path, $self->{cb_rev}->($path),
					$self->{storage_baton}{$pdir}, @arg);
	$self->{notify}->node_status ($path, 'D');
    }
    ++$self->{changes};
}

sub _prop_eq {
    my ($prop1, $prop2) = @_;
    return 0 if defined $prop1 xor defined $prop2;
    return defined $prop1 ? ($prop1 eq $prop2) : 1;
}

sub _merge_prop_content {
    my ($self, $path, $propname, $prop, $pool) = @_;

    if (my $resolver = $self->{prop_resolver}{$propname}) {
	return $resolver->($path, $prop, $pool);
    }

    if (_prop_eq (@{$prop}{qw/base local/})) {
	return ('U', $prop->{new});
    }
    elsif (_prop_eq (@{$prop}{qw/new local/})) {
	return ('g', $prop->{local});
    }

    my $fh = { map {
	my $tgt = defined $prop->{$_} ? \$prop->{$_} : devnull;
	open my $f, '<', $tgt;
	($_ => [$f, ref ($tgt) ? undef : $tgt]);
    } qw/base new local/ };
    $self->prepare_fh ($fh);

    my ($conflict, $mfh) = $self->_merge_text_change ($fh, loc ("Property %1 of %2", $propname, $path), $pool);
    if (!$conflict) {
	local $/;
	$mfh = <$mfh>;
    }
    return ($conflict ? 'C' : 'G', $mfh);
}

sub _merge_prop_change {
    my $self = shift;
    my $path = shift;
    my $pool;
    return unless defined $path;
    return if $_[0] =~ m/^svm:/;
    # special case the the root node that was actually been added
    if ($self->{added}{$path} or
	(!length ($path) and $self->{base_root}->is_revision_root
	 and $self->{base_root}->revision_root_revision == 0)) {
	$self->{notify}->prop_status ($path, 'U');
	return 1;
    }
    my $rpath = $self->{base_anchor} eq '/' ? "/$path" : "$self->{base_anchor}/$path";
    my $prop;
    $prop->{new} = $_[1];
    my ($basepath, $fromrev) = $self->{info}{$path}{baseinfo} ? @{$self->{info}{$path}{baseinfo}} : ($path);
    {
	local $@;
	$prop->{base} = eval { $self->{base_root}->node_prop ($rpath, $_[0], $pool) };
	$prop->{local} = $self->inspector->exist($basepath, $pool)
	    ? $self->{cb_localprop}->($basepath, $_[0], $pool) : undef;
    }
    # XXX: only known props should be auto-merged with default resolver
    $pool = pop @_ if ref ($_[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;
    my ($status, $merged, $skipped) =
	$self->_merge_prop_content ($path, $_[0], $prop, $pool);

    return if $skipped;

    if ($status eq 'C') {
	$self->{cb_conflict}->($path, $_[0]) if $self->{cb_conflict};
	++$self->{conflicts};
    }
    elsif ($status eq 'g') {
	$self->{cb_prop_merged}->($path, $_[0])
	    if $self->{cb_prop_merged};
    }
    else {
	$_[1] = $merged;
    }
    $self->{notify}->prop_status ($path, $status);
    ++$self->{changes};
    return $status eq 'g' ? 0 : 1;
}

sub change_file_prop {
    my ($self, $path, @arg) = @_;
    $self->_merge_prop_change ($path, @arg) or return;
    $self->ensure_open ($path);
    $self->{storage}->change_file_prop ($self->{storage_baton}{$path}, @arg);
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
    $self->_merge_prop_change ($path, @arg) or return;
    $self->{storage}->change_dir_prop ($self->{storage_baton}{$path}, @arg);
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

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
