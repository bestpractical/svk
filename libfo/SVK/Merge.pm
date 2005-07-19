package SVK::Merge;
use strict;
use SVK::Util qw(HAS_SVN_MIRROR find_svm_source find_local_mirror is_executable traverse_history);
use SVK::I18N;
use SVK::Editor::Merge;
use SVK::Editor::Rename;
use SVK::Editor::Translate;
use List::Util qw(min);

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

sub _is_merge_from {
    my ($self, $path, $target, $rev) = @_;
    my $fs = $self->{repos}->fs;
    my $u = $target->universal;
    my $resource = join (':', $u->{uuid}, $u->{path});
    local $@;
    my ($merge, $pmerge) =
	map {SVK::Merge::Info->new (eval { $fs->revision_root ($_)->node_prop
					       ($path, 'svk:merge') })->{$resource}{rev} || 0}
	    ($rev, $rev-1);
    return ($merge != $pmerge);
}

sub _next_is_merge {
    my ($self, $repos, $path, $rev, $checkfrom) = @_;
    return if $rev == $checkfrom;
    my $fs = $repos->fs;
    my $nextrev;

    (traverse_history (
        root     => $fs->revision_root ($checkfrom),
        path     => $path,
        cross    => 0,
        callback => sub {
            return 0 if ($_[1] == $rev); # last
            $nextrev = $_[1];
            return 1;
        }
    ) == 0) or return;

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
    my ($srcinfo, $dstinfo) = map {$self->find_merge_sources ($_)} ($src, $dst);
    my ($basepath, $baserev, $baseentry);
    for (grep {exists $srcinfo->{$_} && exists $dstinfo->{$_}}
	 (sort keys %{ { %$srcinfo, %$dstinfo } })) {
	my ($path) = m/:(.*)$/;
	my $rev = min ($srcinfo->{$_}, $dstinfo->{$_});
	# XXX: should compare revprop svn:date instead, for old dead branch being newly synced back
	($basepath, $baserev, $baseentry) = ($path, $rev, $_)
	    if !$basepath || $rev > $baserev;
    }

    return ($src->new (revision => $self->{baserev}), $self->{baserev})
        if $self->{baserev};

    unless ($basepath) {
	return ($src->new (path => '/', revision => 0), 0)
	    if $self->{baseless};
	die loc("Can't find merge base for %1 and %2\n", $src->path, $dst->path);
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
    $base->{path} = '/' if $base->{revision} == 0;
    return ($base, $dstinfo->{$fs->get_uuid.':'.$src->path} ||
	    ($basepath eq $src->path ? $baserev : 0));
}

sub merge_info {
    my ($self, $target) = @_;
    return SVK::Merge::Info->new
	( $self->{xd}->get_props
	  ($target->root ($self->{xd}), $target->path,
	   $target->copath ($target->{copath_target}))->{'svk:merge'} );
}

sub find_merge_sources {
    my ($self, $target, $verbatim, $noself) = @_;
    my $pool = SVN::Pool->new_default;
    my $info = $self->merge_info ($target->new);

    $target = $target->new->as_depotpath ($self->{xd}{checkout}->get ($target->copath)->{revision})
	if defined $target->{copath};
    $info->add_target ($target, $self->{xd}) unless $noself;

    my $minfo = $verbatim ? $info->verbatim : $info->resolve ($target->{repos});
    return $minfo if $verbatim;

    my $myuuid = $target->{repos}->fs->get_uuid ();

    for (reverse $target->copy_ancestors) {
	my ($path, $rev) = @$_;
	my $entry = "$myuuid:$path";
	$minfo->{$entry} = $rev
	    unless $minfo->{$entry} && $minfo->{$entry} > $rev;
    }

    return $minfo;
}

sub get_new_ticket {
    my ($self, $srcinfo) = @_;
    my $dstinfo = $self->merge_info ($self->{dst});
    # We want the ticket representing src, but not dst.
    my $newinfo = $dstinfo->union ($srcinfo)->del_target ($self->{dst});
    for (sort keys %$newinfo) {
	print loc("New merge ticket: %1:%2\n", $_, $newinfo->{$_}{rev})
	    if !$dstinfo->{$_} || $newinfo->{$_}{rev} > $dstinfo->{$_}{rev};
    }
    return $newinfo->as_string;
}

sub log {
    my ($self, $verbatim) = @_;
    open my $buf, '>', \ (my $tmp = '');
    no warnings 'uninitialized';
    use Sys::Hostname;
    my $print_rev = SVK::Command::Log::_log_remote_rev
	($self->{repos}, $self->{src}->path, $self->{remoterev},
	 '@'.($self->{host} || (split ('\.', hostname, 2))[0]));
    my $sep = $verbatim || $self->{verbatim} ? '' : ('-' x 70)."\n";
    my $cb_log = sub {
	SVK::Command::Log::_show_log
		(@_, $sep, $buf, 1, $print_rev, 0, $self->{verbatim} ? 1 : 0)
		    unless $self->_is_merge_from ($self->{src}->path, $self->{dst}, $_[0]);
    };

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
	require SVK::Command;
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
    my $is_copath = defined($self->{dst}{copath});
    my $notify_target = defined $self->{target} ? $self->{target} : $target;
    my $notify = $self->{notify} || SVK::Notify->new_with_report
	($report, $notify_target, $is_copath);
    if ($target && $dsttarget && $target ne $dsttarget) {
	my $translate = sub { $_[0] =~ s/^\Q$target\E/$dsttarget/ };
	$storage = SVK::Editor::Translate->new (_editor => [$storage],
						translate => $translate);
	SVK::Editor::Merge::cb_translate (\%cb, $translate);
	# if there's notify_target, the translation is done by svk::notify
	$notify->notify_translate ($translate) unless length $notify_target;
    }
    $storage = SVK::Editor::Delay->new ($storage)
	unless $self->{nodelay};
    $storage = $self->track_rename ($storage, \%cb)
	if $self->{track_rename};
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
	  storage => $storage,
	  notify => $notify,
	  g_merge_no_a_change => ($src->path ne $base->path),
	  # if storage editor is E::XD, applytext_delta returns undef
	  # for failed operations, and merge editor should mark them as skipped
	  storage_has_unwritable => $is_copath && !$self->{check_only},
	  allow_conflicts => $is_copath,
	  resolve => $self->resolver,
	  open_nonexist => $self->{track_rename},
	  # XXX: make the prop resolver more pluggable
	  $self->{ticket} ?
	  ( prop_resolver => { 'svk:merge' =>
			  sub { my ($path, $prop) = @_;
				return (undef, undef, 1)
				    if $path eq $target;
				return ('G', SVK::Merge::Info->new
					($prop->{new})->union
					(SVK::Merge::Info->new ($prop->{local}))->as_string);
			    }
			},
	    ticket => 
	    sub { $self->get_new_ticket ($self->merge_info ($src)->add_target ($src)) }
	  ) :
	  ( prop_resolver => { 'svk:merge' => sub { ('G', undef, 1)} # skip
			     }),
	  %cb,
	);
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

sub resolver {
    return undef if $_[0]->{check_only};
    require SVK::Resolve;
    return SVK::Resolve->new (action => $ENV{SVKRESOLVE},
			      external => $ENV{SVKMERGE});
}

package SVK::Merge::Info;

sub new {
    my ($class, $merge) = @_;
    my $minfo = { map { my ($uuid, $path, $rev) = m/(.*?):(.*):(\d+$)/;
			("$uuid:$path" => SVK::Target::Universal->new ($uuid, $path, $rev))
		    } grep { length $_ } split (/\n/, $merge || '') };
    bless $minfo, $class;
    return $minfo;
}

sub add_target {
    my ($self, $target) = @_;
    $target = $target->universal
	if UNIVERSAL::isa ($target, 'SVK::Target');
    $self->{join(':', $target->{uuid}, $target->{path})} = $target;
    return $self;
}

sub del_target {
    my ($self, $target) = @_;
    $target = $target->universal
	if UNIVERSAL::isa ($target, 'SVK::Target');
    delete $self->{join(':', $target->{uuid}, $target->{path})};
    return $self;
}

sub remove_duplicated {
    my ($self, $other) = @_;
    for (keys %$other) {
	if ($self->{$_} && $self->{$_}{rev} <= $other->{$_}{rev}) {
	    delete $self->{$_};
	}
    }
    return $self;
}

sub subset_of {
    my ($self, $other) = @_;
    my $subset = 1;
    for (keys %$self) {
	return unless exists $other->{$_} && $self->{$_}{rev} <= $other->{$_}{rev};
    }
    return 1;
}

sub union {
    my ($self, $other) = @_;
    # bring merge history up to date as from source
    my $new = SVK::Merge::Info->new;
    for (keys %{ { %$self, %$other } }) {
	if ($self->{$_} && $other->{$_}) {
	    $new->{$_} = $self->{$_}{rev} > $other->{$_}{rev}
		? $self->{$_} : $other->{$_};
	}
	else {
	    $new->{$_} = $self->{$_} ? $self->{$_} : $other->{$_};
	}
    }
    return $new;
}

sub resolve {
    my ($self, $repos) = @_;
    my $uuid = $repos->fs->get_uuid;
    return { map { my $local = $self->{$_}->local ($repos);
		   $local ? ("$uuid:$local->{path}" => $local->{revision}) : ()
	       } keys %$self };
}

sub verbatim {
    my ($self) = @_;
    return { map { $_ => $self->{$_}{rev} } keys %$self };
}

sub as_string {
    my $self = shift;
    return join ("\n", map {"$_:$self->{$_}{rev}"} sort keys %$self);
}

=head1 TODO

Document the merge and ticket tracking mechanism.

=head1 SEE ALSO

L<SVK::Editor::Merge>, L<SVK::Command::Merge>, Star-merge from GNU Arch

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
