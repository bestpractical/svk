package SVK::Target;
use strict;
our $VERSION = $SVK::VERSION;
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( get_anchor catfile abs2rel HAS_SVN_MIRROR IS_WIN32
		  find_prev_copy );
use SVK::Target::Universal;
use Clone;

=head1 NAME

SVK::Target - SVK targets

=head1 SYNOPSIS

 See below

=head1 DESCRIPTION

For a target given in command line, the class is about locating the
path in the depot, the checkout path, and others.

=cut

sub new {
    my ($class, @arg) = @_;
    my $self = ref $class ? clone ($class) :
	bless {}, $class;
    %$self = (%$self, @arg);
    $self->refresh_revision unless defined $self->{revision};
    return $self;
}

sub refresh_revision {
    my ($self) = @_;
    $self->{revision} = $self->{repos}->fs->youngest_rev;
}

sub clone {
    my ($self) = @_;
    my $cloned = Clone::clone ($self);
    $cloned->{repos} = $self->{repos};
    return $cloned;
}

sub root {
    my ($self, $xd) = @_;
    if ($self->{copath}) {
	$xd->xdroot (%$self);
    }
    else {
	SVK::XD::Root->new ($self->{repos}->fs->revision_root
			    ($self->{revision}));
    }
}

=head2 same_repos

Returns true if all C<@other> targets are from the same repository

=cut

sub same_repos {
    my ($self, @other) = @_;
    for (@other) {
	return 0 if $self->{repos} ne $_->{repos};
    }
    return 1;
}

=head2 same_source

Returns true if all C<@other> targets are mirrored from the same source

=cut

sub same_source {
    my ($self, @other) = @_;
    return 0 unless HAS_SVN_MIRROR;
    return 0 unless $self->same_repos (@other);
    my $mself = SVN::Mirror::is_mirrored ($self->{repos}, $self->{path});
    for (@other) {
	my $m = SVN::Mirror::is_mirrored ($_->{repos}, $_->{path});
	return 0 if $m xor $mself;
	return 0 if $m && $m->{target_path} ne $m->{target_path};
    }
    return 1;
}

sub anchorify {
    my ($self) = @_;
    die "anchorify $self->{depotpath} already with targets: ".join(',', @{$self->{targets}})
	if exists $self->{targets}[0];
    ($self->{path}, $self->{targets}[0], $self->{depotpath}) =
	get_anchor (1, $self->{path}, $self->{depotpath});
    ($self->{copath}, $self->{copath_target}) = get_anchor (1, $self->{copath})
	if $self->{copath};
    # XXX: prepend .. if exceeded report?
    ($self->{report}) = get_anchor (0, $self->{report})
	if $self->{report}
}

=head2 normalize

Normalize the revision to the last changed one.

=cut

sub normalize {
    my ($self) = @_;
    my $fs = $self->{repos}->fs;
    my $root = $fs->revision_root ($self->{revision});
    $self->{revision} = ($root->node_history ($self->path)->prev(0)->location)[1]
	unless $self->{revision} == $root->node_created_rev ($self->path);
}

=head2 as_depotpath

Makes target depotpath. Takes C<$revision> number optionally.

=cut

sub as_depotpath {
    my ($self, $revision) = @_;
    delete $self->{copath};
    $self->{revision} = $revision if defined $revision;
    return $self;
}

=head2 path

Returns the full path of the target even if anchorified.

=cut

sub path {
    my ($self) = @_;
    $self->{targets}[0]
	? "$self->{path}/$self->{targets}[0]" : $self->{path};
}

=head2 copath

Return the checkout path of the target, optionally with additional
path component.

=cut

my $_copath_catsplit = $^O eq 'MSWin32' ? \&catfile :
sub { defined $_[0] && length $_[0] ? "$_[0]/$_[1]" : $_[1] };

sub copath {
    my $self = shift;
    my $copath = ref ($self) ? $self->{copath} : shift;
    my $paths = shift;
    return $copath unless defined $paths && length ($paths);
    return $_copath_catsplit->($copath, $paths);
}

=head2 descend

Makes target descend into C<$entry>

=cut

sub descend {
    my ($self, $entry) = @_;
    $self->{depotpath} .= "/$entry";
    $self->{path} .= "/$entry";

    if (defined $self->{copath}) {
	$self->{report} = catfile ($self->{report}, $entry);
	$self->{copath} = catfile ($self->{copath}, $entry);
    }
    else {
	$self->{report} = "$self->{report}/$entry";
    }
}

=head2 universal

Returns corresponding L<SVK::Target::Universal> object.

=cut

sub universal {
    SVK::Target::Universal->new ($_[0]);
}

sub contains_copath {
    my ($self, $copath) = @_;
    foreach my $base (@{$self->{targets} || []}) {
	if ($copath ne abs2rel ($copath, $self->copath ($base))) {
	    return 1;
	}
    }
    return 0;
}

sub contains_mirror {
    require SVN::Mirror;
    my ($self) = @_;
    my $path = $self->{path};
    $path .= '/' unless $path eq '/';
    return map { substr ("$_/", 0, length($path)) eq $path ? $_ : () }
	SVN::Mirror::list_mirror ($self->{repos});
}

=head2 depotname

Returns depotname of the target

=cut

sub depotname {
    my $self = shift;

    $self->{depotpath} =~ m!^/([^/]*)!
      or die loc("'%1' does not contain a depot name.\n", $self->{depotpath});

    return $1;
}

# depotpath only for now
# cache revprop:
# svk:copy_cache

# svk:copy_cache_prev points to the revision in the depot that the
# previous copy happens.

sub copy_ancestors {
    my $self = shift;
    my $fs = $self->{repos}->fs;
    my $t = $self->new->as_depotpath;
    my @result;
    while (my ($copyto, $copyfrom_rev, $copyfrom_path) = $t->nearest_copy) {
	$t->{path} = $copyfrom_path;
	$t->{revision} = $copyfrom_rev;
	push @result, [@{$t}{qw(path revision)}];
	# if the original target is anchorified, do so too.
	delete $t->{targets}, $t->anchorify if exists $self->{targets}[0];
    }
    return @result;
}

use List::Util qw(min);

# given a root object and a path, returns the revision where it's ancestor
# is from another path.
sub nearest_copy {
    my ($root, $path) = @_;
    if (ref ($root) eq __PACKAGE__) {
	($root, $path) = ($root->root, $root->path);
    }
    my $fs = $root->fs;
    my $spool = SVN::Pool->new_default;
    my $old_pool = SVN::Pool->new;
    my $new_pool = SVN::Pool->new;

    # normalize
    my $histself = $root->node_history ($path)->prev(0);
    my $rev = ($histself->location)[1];
    my $lastcopy;
    while (1) {
	# Find history_prev revision, if the path is different, bingo.
	my $hist = $histself->prev(1, $new_pool) or last; # no more history
	my ($hppath, $hprev) = $hist->location;
	return ($rev, $hprev, $hppath) if $hppath ne $path; # got it
	$histself = $hist;

	# Find nearest copy of the current revision (up to but *not*
	# including the revision itself). If the copy contains us, bingo.
	my ($prev, $copy) = find_prev_copy ($fs,
					    $lastcopy && $lastcopy == $rev
					    ? $rev-1
					    : $rev);
	last unless $prev; # no more copies
	if (my ($fromrev, $frompath) = _copies_contain_path ($copy, $path)) {
	    # there were copy, but the descendent might not exist there
	    last unless $fs->revision_root ($fromrev)->check_path ($frompath);
	    return ($prev, $fromrev, $frompath);
	}
	elsif ($prev < $hprev) {
	    # Reset the hprev root to this earlier revision to avoid infinite looping
	    last unless $fs->revision_root ($prev)->check_path ($path);
	    $root = $fs->revision_root ($prev, $new_pool);
	    $histself = $root->node_history ($path)->prev(0, $new_pool);
	}
	$lastcopy = $prev;
	# Continue testing on min (history_prev, prev_copy)
	$rev = min ($prev, $hprev);
        $old_pool->clear;
	$spool->clear;
        ($old_pool, $new_pool) = ($new_pool, $old_pool);
    }
    return;
}

sub _copies_contain_path {
    my ($copy, $path) = @_;
    my ($match) = grep { index ("$path/", "$_/") == 0 }
	sort { length $b <=> length $a } keys %$copy;
    return unless $match;
    $path =~ s/^\Q$match\E/$copy->{$match}[1]/;
    return ($copy->{$match}[0], $path);
}

=head2 related_to

Check if C<$self> is related to another target.

=cut

sub related_to {
    my ($self, $other) = @_;
    # XXX: when two related paths are mirrored separatedly, need to
    # use hooks or merge tickets to decide if they are related.
    return SVN::Fs::check_related
	($self->root->node_id ($self->path),
	 $other->root->node_id ($other->path));
}

=head2 copied_from ($want_mirror)

Return the nearest copy target that still exists.  If $want_mirror is true,
only return one that was mirrored from somewhere.

=cut

sub copied_from {
    my ($self, $want_mirror) = @_;

    my $target = $self->new;
    $target->{report} = '';
    $target->as_depotpath;

    my $root = $target->root;

    while ((undef, $target->{revision}, $target->{path}) = $target->nearest_copy) {
	# Check for existence.
	if ($root->check_path ($target->{path}) == $SVN::Node::none) {
	    next;
	}

	# Check for mirroredness.
	if ($want_mirror and HAS_SVN_MIRROR) {
	    my ($m, $mpath) = SVN::Mirror::is_mirrored (
		$target->{repos}, $target->{path}
	    );
	    $m->{source} or next;
	}

	# It works!  Let's update it to the latest revision and return
	# it as a fresh depot path.
	$target->{depotpath} = '/' . $target->depotname . $target->path;
	$target->refresh_revision;
	$target->as_depotpath;

	delete $target->{targets};
	return $target;
    }

    return undef;
}

sub report_copath {
    my ($self, $copath) = @_;
    my $report = length ($self->{report}) ? $self->{report} : undef;
    abs2rel ($copath, $self->{copath} => $report);
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
