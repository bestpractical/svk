package SVK::Merge;
use strict;
use SVK::Util qw (find_svm_source find_local_mirror svn_mirror);
use SVK::I18N;

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, $class;
    %$self = @arg;
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
    my ($self, $repos, $src, $dst) = @_;
    my ($srcinfo, $dstinfo) = map {$self->find_merge_sources ($repos, $_)} ($src, $dst);
    my ($basepath, $baserev, $baseentry);
    my $fs = $repos->fs;
    for (grep {exists $srcinfo->{$_} && exists $dstinfo->{$_}}
	 (sort keys %{ { %$srcinfo, %$dstinfo } })) {
	my ($path) = m/:(.*)$/;
	my $rev = $srcinfo->{$_} < $dstinfo->{$_} ? $srcinfo->{$_} : $dstinfo->{$_};
	# XXX: shuold compare revprop svn:date instead, for old dead branch being newly synced back
	($basepath, $baserev, $baseentry) = ($path, $rev, $_)
	    if !$basepath || $rev > $baserev;
    }

    my $yrev = $fs->youngest_rev;
    if (!$basepath) {
	die loc("Can't find merge base for %1 and %2\n", $src, $dst)
	  unless $self->{baseless} or $self->{base};

	unless ($baserev = $self->{base}) {
	    # baseless merge
	    my $pool = SVN::Pool->new_default;
	    my $hist = $fs->revision_root($yrev)->node_history($src);
	    $pool->clear, $baserev = ($hist->location)[1]
		while $hist = $hist->prev(0);
	}

	return ($src, $baserev, $baserev);
    }

    if ($basepath ne $src && $basepath ne $dst) {
	my ($fromrev, $torev) = ($srcinfo->{$baseentry}, $dstinfo->{$baseentry});
	($fromrev, $torev) = ($torev, $fromrev) if $torev < $fromrev;
	if (my ($mrev, $merge) =
	    $self->_next_is_merge ($repos, $basepath, $fromrev, $torev)) {
	    my $minfo = SVK::Merge::Info->new ($merge);
	    my $root = $fs->revision_root ($yrev);
	    my ($srcinfo, $dstinfo) = map { SVK::Merge::Info->new ($root->node_prop ($_, 'svk:merge')) }
		($src, $dst);
	    $baserev = $mrev
		if $minfo->subset_of ($srcinfo) && $minfo->subset_of ($dstinfo);
	}
    }

    return ($basepath, $baserev, $dstinfo->{$fs->get_uuid.':'.$src} || $baserev);
}

sub find_merge_sources {
    my ($self, $repos, $path, $verbatim, $noself) = @_;
    my $pool = SVN::Pool->new_default;

    my $fs = $repos->fs;
    my $yrev = $fs->youngest_rev;
    my $root = $fs->revision_root ($yrev);
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
	    my ($uuid, $path, $rev) = find_svm_source ($repos, $path);
	    $minfo->{join(':', $uuid, $path)} = $rev;
	}
	return $minfo;
    }
    else {
	$minfo->{join(':', $myuuid, $path)} = ($root->node_history ($path)->prev (0)->location)[1]
	    unless $noself;
    }

    my %ancestors = $self->copy_ancestors ($repos, $path, $yrev, 1);
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
    my ($self, $repos, $src, $dst) = @_;

    my $srcinfo = $self->find_merge_sources ($repos, $src, 1);
    my $dstinfo = $self->find_merge_sources ($repos, $dst, 1);
    my ($uuid, $newinfo);

    # bring merge history up to date as from source
    ($uuid, $dst) = find_svm_source ($repos, $dst);
    for (sort keys %{ { %$srcinfo, %$dstinfo } }) {
	next if $_ eq "$uuid:$dst";
	no warnings 'uninitialized';
	$newinfo->{$_} = $srcinfo->{$_} > $dstinfo->{$_} ? $srcinfo->{$_} : $dstinfo->{$_};
	print loc("New merge ticket: %1:%2\n", $_, $newinfo->{$_})
	    if !$dstinfo->{$_} || $newinfo->{$_} > $dstinfo->{$_};
    }

    return join ("\n", map {"$_:$newinfo->{$_}"} sort keys %$newinfo);
}

sub log {
    my $self = shift;
    open my $buf, '>', \ (my $tmp);
    SVK::Command::Log::do_log (@_, 0, 0, 0, 1, $buf);
    $tmp =~ s/^/ /mg;
    return $tmp;
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

1;

