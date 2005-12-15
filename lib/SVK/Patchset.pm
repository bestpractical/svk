package SVK::Patchset;
use strict;
use SVK::Util qw(get_depot_anchor);
use SVK::Editor::Combiner;

=head1 NAME

SVK::Patchset - Calculate patch dependency

=head1 SYNOPSIS



=head1 DESCRIPTION



=cut

# THIS CODE IS NOT READY FOR GENERAL USE

# TODO:
# - better constructor, and maybe put $repos into $self
# - put uuid:rev instead of raw rev

sub recalculate {
    my ($self, $repos) = @_;
    my $fs = $repos->fs;
    my $rev = $fs->youngest_rev;
    while ($rev) {
	my @revs = $self->dependencies ($repos, $rev);
	--$rev;
    }
}

use List::Util qw(reduce);
use List::MoreUtils qw(uniq);

# find out all the nodes in tree $rev that is depended on by $leaf
sub dependencies_in_tree {
    my ($self, $repos, $rev, $leaf) = @_;

#    Carp::cluck "+ dep in tree $rev vs $leaf";
    if ($self->rev_depends_on ($repos, $rev, $leaf)) {
	return ($leaf);
    }
    my @pp = $self->dependencies ($repos, $leaf);
    my @fuck;
    for my $p (@pp) {
	if ($self->rev_depends_on ($repos, $rev, $p)) {
	    push @fuck, $p;
	}
    }
    return @fuck;
}

our %CACHE;

sub all_dependencies {
    my ($self, $repos, $rev) = @_;
    my $cache = $CACHE{$repos} ||= {};

    return $cache->{$rev} ||=
	[uniq map { ($_, @{$self->all_dependencies($repos, $_)} ) }
	 $self->dependencies ($repos, $rev)];
}

sub dependencies {
    my ($self, $repos, $rev) = @_;
    return if $rev == 0;
    my $pool = SVN::Pool->new_default;
    my $fs = $repos->fs;
    my $parents = $fs->revision_prop ($rev, 'svk:parents');
    if (defined $parents) {
	$parents = [uniq split /,/, $parents];
    }
    else {
	# Here, we use history traversal and limit the domain of
	# changes.  The domain grows if the change contains paths
	# outside the current domain.
	my $leaf = $rev;
	my %parents = ($rev => 1);
	my $anchor;
	my $spool = SVN::Pool->new_default;
	while ($leaf > 1) {
	    my $root = $fs->revision_root ($leaf);
	    $anchor = anchor_of (defined $anchor ? $anchor : (),
				 anchor_in_change ($fs, $root));
	    $root->check_path($anchor) or last; # XXX: might be Deleted
	    my $hist = $root->node_history ($anchor)->prev(0)->prev(0) or last;
	    $leaf = ($hist->location)[1];
	    if (defined $fs->revision_prop ($leaf, 'svk:children')) {
		# if this is not a leaf node, we skip it if it's already
		# marked as our ancestry
		next if $parents{$leaf};
	    }
	    my @parents = $self->dependencies_in_tree ($repos, $rev, $leaf);
	    for my $p (@parents) {
		++$parents{$_}
		    for @{$self->all_dependencies ($repos, $p)};
	    }

	    push @$parents, @parents;
	    $spool->clear;
	}
	$parents ||= [];
	# get rid of non-immediate parents.
	@$parents = uniq grep { !$parents{$_} } @$parents;
	$fs->change_rev_prop ($rev, 'svk:parents', join(',', @$parents));
	for (@$parents) {
	    $fs->change_rev_prop ($_, 'svk:children',
				  join(',', $rev, split /,/, ($fs->revision_prop ($_, 'svk:children') || '')));
	    $spool->clear;
	}
    }
    return @$parents;
}


my %DEPCACHE;

sub rev_depends_on {
    my ($self, $repos, $rev, $prev) = @_;
    my $pool = SVN::Pool->new_default;
    my $xd = $self->{xd};
    Carp::confess unless $prev;

    my $cache = $DEPCACHE{$repos} ||= {};
    return $cache->{$rev}{$prev} if exists $cache->{$rev}{$prev};
    if (defined $repos->fs->revision_prop ($rev, 'svk:parents')) {

	my @fo = grep { $_ == $prev } @{$self->all_dependencies($repos, $rev)};
	return $cache->{$rev}{$prev} = (@fo ? 1 : 0);
    }

    my $txn = $repos->fs_begin_txn_for_commit ($prev-1, 'svk', 'not for commit');

    my $editor = SVK::Editor::Combiner->new
	($repos->get_commit_editor2 ($txn, '', '/', undef, undef, sub { }));
    my $fs = $repos->fs;

    require SVK::Editor::Merge;
    require SVK::Notify;
    require Encode;
    my $meditor = SVK::Editor::Merge->new
	( base_anchor => '',
	  base_root => $fs->revision_root ($rev-1),
	  notify => SVK::Notify->new(quiet => 1),
	  storage => $editor,
	  anchor => '',
	  target => '',
	  send_fulltext => 1,
	  prop_resolver => { 'svk:merge' => sub { ('G', undef, 1)} },
	  SVK::Editor::Merge->cb_for_root
	  ($fs->revision_root($prev-1), '', $prev-1));

    $xd->depot_delta ( oldroot => $fs->revision_root ($rev-1),
		       newroot => $fs->revision_root ($rev),
		       oldpath => ['/', ''],
		       newpath => '/',
		       editor => $meditor,
		     );
    $txn->abort;

    return $cache->{$rev}{$prev} = ($meditor->{conflicts} || $meditor->{skipped});
}

sub anchor_of {
    my $anchor;
    for (@_) {
	unless (defined $anchor) {
	    $anchor = $_;
	    next;
	}
	while ($anchor ne '/' && index ("$_/", "$anchor/") != 0) {
	    ($anchor) = get_depot_anchor (0, $anchor);
	}
    }
    return $anchor;
}

sub anchor_in_change {
    my ($fs, $root) = @_;
    my $changed = $root->paths_changed;
    return anchor_of (keys %$changed);
}


1;

__END__

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
