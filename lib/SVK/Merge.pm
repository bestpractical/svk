package SVK::Merge;
use strict;
use SVK::Util qw (find_svm_source find_local_mirror svn_mirror);
use SVK::I18N;
use SVK::Editor::Merge;
use SVK::Editor::Rename;
use SVK::Editor::Translate;

=head1 NAME

SVK::Merge - Merge context class

=head1 SYNOPSIS

  use SVK::Merge;

  SVK::Merge->auto (repos => $repos, src => $src, dst => $dst)->run ($editor, %cb);

=head1 DESCRIPTION

The C<SVK::Merge> class is for representing merge contexts, mainly
including what delta is used for this merge, and what target the delta
applies to.

Given the 3 L<SVK::Target> objects:

=over

=item src

=item dst

=item base

=back

C<SVK::Merge> will be applying I<delta> (C<base>, C<src>) to C<dst>.

=head1 CONSTRUCTORS

=head2 new

Takes parameters the usual way.

=head2 auto

Like new, but the C<base> object will be found automatically as the
nearest ancestor of C<src> and C<dst>.

=head1 METHODS

=over

=cut

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, $class;
    %$self = @arg;
    return $self;
}

sub auto {
    my $self = new (@_);
    @{$self}{qw/base fromrev/} = $self->find_merge_base (@{$self}{qw/src dst/});
    return $self;
}

sub _next_is_merge {
    my ($self, $repos, $path, $rev, $checkfrom) = @_;
    return if $rev == $checkfrom;
    my $fs = $repos->fs;
    my $pool = SVN::Pool->new_default;
    my $hist = $fs->revision_root ($checkfrom)->node_history ($path);
    my $newhist = $hist->prev (0);
    my $nextrev;
    while ($hist = $newhist) {
	$pool->clear;
	$hist = $newhist;
	$newhist = $hist->prev (0);
	$nextrev = ($hist->location)[1], last
	    if $newhist && ($newhist->location)[1] == $rev;
    }
    return unless $nextrev;
    my ($merge, $pmerge) =
	map {$fs->revision_root ($_)->node_prop ($path, 'svk:merge') || ''}
	    ($nextrev, $rev);
    return if $merge eq $pmerge;
    return ($nextrev, $merge);
}

sub find_merge_base {
    my ($self, $src, $dst) = @_;
    my $repos = $self->{repos};
    my $fs = $repos->fs;
    my $yrev = $fs->youngest_rev;
    my ($srcinfo, $dstinfo) = map {$self->find_merge_sources ($repos, $_->path, $_->{revision})} ($src, $dst);
    my ($basepath, $baserev, $baseentry);
    for (grep {exists $srcinfo->{$_} && exists $dstinfo->{$_}}
	 (sort keys %{ { %$srcinfo, %$dstinfo } })) {
	my ($path) = m/:(.*)$/;
	my $rev = $srcinfo->{$_} < $dstinfo->{$_} ? $srcinfo->{$_} : $dstinfo->{$_};
	# XXX: shuold compare revprop svn:date instead, for old dead branch being newly synced back
	($basepath, $baserev, $baseentry) = ($path, $rev, $_)
	    if !$basepath || $rev > $baserev;
    }

    if (!$basepath) {
	die loc("Can't find merge base for %1 and %2\n", $src->path, $dst->path)
	    unless $self->{baseless} or $self->{base};

	return ($src->new (revision => $self->{baserev}), $self->{baserev})
	    if $self->{baserev};

	return ($src->new (path => '/', revision => 0), 0);
    }

    # XXX: document this, cf t/07smerge-foreign.t
    if ($basepath ne $src->path && $basepath ne $dst->path) {
	my ($fromrev, $torev) = ($srcinfo->{$baseentry}, $dstinfo->{$baseentry});
	($fromrev, $torev) = ($torev, $fromrev) if $torev < $fromrev;
	if (my ($mrev, $merge) =
	    $self->_next_is_merge ($repos, $basepath, $fromrev, $torev)) {
	    my $minfo = SVK::Merge::Info->new ($merge);
	    my $root = $fs->revision_root ($yrev);
	    my ($srcinfo, $dstinfo) = map { SVK::Merge::Info->new ($root->node_prop ($_->path, 'svk:merge')) }
		($src, $dst);
	    $baserev = $mrev
		if $minfo->subset_of ($srcinfo) && $minfo->subset_of ($dstinfo);
	}
    }

    my $base = $src->new (path => $basepath, revision => $baserev, targets => undef);
    $base->anchorify if exists $src->{targets}[0];
    return ($base, $dstinfo->{$fs->get_uuid.':'.$src} || $baserev);
}

sub find_merge_sources {
    my ($self, $repos, $path, $rev, $verbatim, $noself) = @_;
    my $pool = SVN::Pool->new_default;

    my $fs = $repos->fs;
    my $root = $fs->revision_root ($rev);
    my $minfo = $root->node_prop ($path, 'svk:merge');
    my $myuuid = $fs->get_uuid ();
    if ($minfo) {
	$minfo = { map {my ($uuid, $path, $rev) = split ':', $_;
                        ($uuid, $path, $rev) =
			    ($myuuid, find_local_mirror ($repos, $uuid, $path, $rev))
				unless $verbatim || $uuid eq $myuuid;
                        $rev ? ("$uuid:$path" => $rev) : ()
		    } split ("\n", $minfo) };
    }
    if ($verbatim) {
	unless ($noself) {
	    my ($uuid, $path, $rev) = find_svm_source ($repos, $path, $rev);
	    $minfo->{join(':', $uuid, $path)} = $rev;
	}
	return $minfo;
    }
    else {
	$minfo->{join(':', $myuuid, $path)} = ($root->node_history ($path)->prev (0)->location)[1]
	    unless $noself;
    }

    my %ancestors = $self->copy_ancestors ($repos, $path, $rev, 1);
    for (sort keys %ancestors) {
	my $rev = $ancestors{$_};
	$minfo->{$_} = $rev
	    unless $minfo->{$_} && $minfo->{$_} > $rev;
    }

    return $minfo;
}

sub copy_ancestors {
    my ($self, $repos, $path, $rev, $nokeep) = @_;
    my $fs = $repos->fs;
    my $root = $fs->revision_root ($rev);
    $rev = $root->node_created_rev ($path);

    my $spool = SVN::Pool->new_default_sub;
    my ($found, $hitrev, $source) = (0, 0, '');
    my $myuuid = $fs->get_uuid ();
    my $hist = $root->node_history ($path);
    my ($hpath, $hrev);

    while ($hist = $hist->prev (1)) {
	$spool->clear;
	($hpath, $hrev) = $hist->location ();
	if ($hpath ne $path) {
	    $found = 1;
	}
	elsif (defined ($source = $fs->revision_prop ($hrev, "svk:copied_from:$path"))) {
	    $hitrev = $hrev;
	    last unless $source;
	    my $uuid;
	    ($uuid, $hpath, $hrev) = split ':', $source;
	    if ($uuid ne $myuuid) {
		my ($m, $mpath);
		if (svn_mirror &&
		    (($m, $mpath) = SVN::Mirror::has_local ($repos, "$uuid:$path"))) {
		    ($hpath, $hrev) = ($m->{target_path}, $m->find_local_rev ($hrev));
		    # XXX: WTF? need test suite for this
		    $hpath =~ s/\Q$mpath\E$//;
		}
		else {
		    return ();
		}
	    }
	    $found = 1;
	}
	last if $found;
    }

    $source = '' unless $found;
    if (!$found || $hitrev != $hrev) {
	$fs->change_rev_prop ($hitrev, "svk:copied_from:$path", undef)
	    unless $hitrev || $fs->revision_prop ($hitrev, "svk:copied_from_keep:$path");
	$source ||= join (':', $myuuid, $hpath, $hrev) if $found;
	if ($hitrev != $rev) {
	    $fs->change_rev_prop ($rev, "svk:copied_from:$path", $source);
	    $fs->change_rev_prop ($rev, "svk:copied_from_keep:$path", 'yes')
		unless $nokeep;
	}
    }
    return () unless $found;
    return ("$myuuid:$hpath" => $hrev, $self->copy_ancestors ($repos, $hpath, $hrev));
}

sub get_new_ticket {
    my ($self) = @_;
    my ($srcinfo, $dstinfo) = map {$self->find_merge_sources ($self->{repos}, $_->path, $_->{revision}, 1)}
	@{$self}{qw/src dst/};
    my ($newinfo);
    # bring merge history up to date as from source
    my ($uuid, $dstpath) = find_svm_source ($self->{repos}, $self->{dst}->path);
    for (sort keys %{ { %$srcinfo, %$dstinfo } }) {
	next if $_ eq "$uuid:$dstpath";
	no warnings 'uninitialized';
	$newinfo->{$_} = $srcinfo->{$_} > $dstinfo->{$_} ? $srcinfo->{$_} : $dstinfo->{$_};
	print loc("New merge ticket: %1:%2\n", $_, $newinfo->{$_})
	    if !$dstinfo->{$_} || $newinfo->{$_} > $dstinfo->{$_};
    }

    return join ("\n", map {"$_:$newinfo->{$_}"} sort keys %$newinfo);
}

sub log {
    my ($self, $verbatim) = @_;
    open my $buf, '>', \ (my $tmp);
    no warnings 'uninitialized';
    use Sys::Hostname;
    my $print_rev = SVK::Command::Log::_log_remote_rev
	($self->{repos}, $self->{src}->path, $self->{remoterev},
	 '@'.($self->{host} || (split ('\.', hostname, 2))[0]));
    my $sep = $verbatim ? '' : ('-' x 70)."\n";
    my $cb_log = sub { SVK::Command::Log::_show_log
	    (@_, $sep, $buf, 1, $print_rev) };

    print $buf " $sep" if $sep;
    SVK::Command::Log::do_log (repos => $self->{repos}, path => $self->{src}->path,
			       fromrev => $self->{fromrev}+1, torev => $self->{src}{revision},
			       cb_log => $cb_log);
    return $tmp;
}

=item info

Return a string about how the merge is done.

=cut

sub info {
    my $self = shift;
    return loc("Auto-merging (%1, %2) %3 to %4 (base %5:%6).\n",
	       $self->{fromrev}, $self->{src}{revision}, $self->{src}->path,
	       $self->{dst}->path, $self->{base}->path, $self->{base}{revision});
}

sub _collect_renamed {
    my ($renamed, $pathref, $reverse, $rev, $root, $paths, $props) = @_;
    my $entries;
    my $path = $$pathref;
    for (keys %$paths) {
	my $entry = $paths->{$_};
	my $action = $SVK::Command::Log::chg->[$entry->change_kind];
	$entries->{$_} = [$action , $action eq 'D' ? (-1) : $root->copied_from ($_)];
	# anchor is copied
	if ($action eq 'A' && $entries->{$_}[1] != -1 &&
	    ($path eq $_ || "$_/" eq substr ($path, 0, length($_)+1))) {
	    $path =~ s/^\Q$_\E/$entries->{$_}[2]/;
	    $$pathref = $path;
	}
    }
    for (keys %$entries) {
	my $entry = $entries->{$_};
	my $from = $entry->[2] or next;
	if (exists $entries->{$from} && $entries->{$from}[0] eq 'D') {
	    s|^\Q$path\E/|| or next;
	    $from =~ s|^\Q$path\E/|| or next;
	    push @$renamed, $reverse ? [$from, $_] : [$_, $from];
	}
    }
}

sub track_rename {
    my ($self, $editor, $cb) = @_;

    my ($base) = $self->find_merge_base (@{$self}{qw/base dst/});
    my ($renamed, $path) = ([]);

    print "Collecting renames, this might take a while.\n";
    for (0..1) {
	my $target = $self->{('base', 'dst')[$_]};
	my $path = $target->path;
	SVK::Command::Log::do_log (repos => $self->{repos}, path => $path, verbose => 1,
				   torev => $base->{revision}+1, fromrev => $target->{revision},
				   cb_log => sub {_collect_renamed ($renamed, \$path, $_, @_)});
    }
    return $editor unless @$renamed;

    my $rename_editor = SVK::Editor::Rename->new (editor => $editor, rename_map => $renamed);
    SVK::Editor::Merge::cb_translate ($cb, sub {$_[0] = $rename_editor->rename_check ($_[0])});
    return $rename_editor;
}

=item run

Given the storage editor and L<SVK::Editor::Merge> callbacks, apply
the merge to the storage editor. Returns the number of conflicts.

=back

=cut

sub run {
    my ($self, $storage, %cb) = @_;
    my ($base, $src) = @{$self}{qw/base src/};
    my $base_root = $self->{base_root} || $base->root ($self->{xd});
    # XXX: for merge editor; this should really be in SVK::Target
    my ($report, $target) = ($self->{report}, $src->{targets}[0] || '');
    my $dsttarget = $self->{dst}{targets}[0];
    if ($target && $dsttarget && $target ne $dsttarget) {
	my $translate = sub { $_[0] =~ s/^\Q$target\E/$dsttarget/ };
	$storage = SVK::Editor::Translate->new (_editor => [$storage],
						translate => $translate);
	SVK::Editor::Merge::cb_translate (\%cb, $translate);
    }
    $storage = SVK::Editor::Delay->new ($storage)
	unless $self->{nodelay};
    $storage = $self->track_rename ($storage, \%cb)
	if $self->{track_rename};
    my $notify = $self->{notify} || SVK::Notify->new_with_report
	($report, defined $self->{target} ? $self->{target} : $target);
    if ($storage->can ('rename_check')) {
	my $flush = $notify->{cb_flush};
	$notify->{cb_flush} = sub {
	    my ($path, $st) = @_;
	    my $newpath = $storage->rename_check ($path);
	    $flush->($path, $st, $path eq $newpath ? undef : $newpath) };
    }
    my $editor = SVK::Editor::Merge->new
	( anchor => $src->{path},
	  base_anchor => $base->{path},
	  base_root => $base_root,
	  target => $target,
	  send_fulltext => $cb{mirror} ? 0 : 1,
	  storage => $storage,
	  notify => $notify,
	  allow_conflicts => defined $self->{dst}{copath},
	  open_nonexist => $self->{track_rename},
	  cb_merged => $self->{ticket} ?
	  sub { my ($editor, $baton, $pool) = @_;
		my $func = $base_root->check_path ($base->path) == $SVN::Node::file ?
		    'change_file_prop' : 'change_dir_prop';
		$editor->$func
		    ($baton, 'svk:merge', $self->get_new_ticket, $pool);
	    } : undef,
	  %cb,
	);
    $editor->{external} = $ENV{SVKMERGE}
	if !$self->{check_only} && $ENV{SVKMERGE} && -x (split (' ', $ENV{SVKMERGE}))[0];
    SVK::XD->depot_delta
	    ( oldroot => $base_root, newroot => $src->root,
	      oldpath => [$base->{path}, $base->{targets}[0] || ''],
	      newpath => $src->path,
	      no_recurse => $self->{no_recurse}, editor => $editor,
	    );
    print loc("%*(%1,conflict) found.\n", $editor->{conflicts}) if $editor->{conflicts};
    print loc("%*(%1,file) skipped, you might want to rerun merge with --track-rename.\n",
	      $editor->{skipped}) if $editor->{skipped} && !$self->{track_rename} && !$self->{auto};

    return $editor->{conflicts};
}

package SVK::Merge::Info;

# XXX: cleanup minfo handling and put them here

sub new {
    my ($class, $merge) = @_;

    my $minfo = { map {my ($uuid, $path, $rev) = split ':', $_;
		       ("$uuid:$path" => $rev)
		   } split ("\n", $merge) };
    bless $minfo, $class;
    return $minfo;
}

sub subset_of {
    my ($self, $other) = @_;
    my $subset = 1;
    for (keys %$self) {
	return unless exists $other->{$_} && $self->{$_} <= $other->{$_};
    }
    return 1;
}

=head1 TODO

Document the merge and ticket tracking mechanism.

=head1 SEE ALSO

L<SVK::Editor::Merge>, L<SVK::Command::Merge>, Star-merge from GNU Arch

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
