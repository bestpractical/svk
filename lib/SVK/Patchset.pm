package SVK::Patchset;
use strict;
use SVK::Util qw(get_depot_anchor);

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

sub dependencies_in_tree {
    my ($self, $repos, $rev, $leaf) = @_;

    my @pp = $self->dependencies ($repos, $leaf);
    if ($self->rev_depends_on ($repos, $rev, $leaf)) {
	my %filter = map { $_ => 1} @pp;
	return grep { !$filter{$_} } $leaf;
    }

    return reduce { $a == $b ? $a : ($a, $b)} sort # uniq
	map { $self->dependencies_in_tree ($repos, $rev, $_) } @pp;
}

sub dependencies {
    my ($self, $repos, $rev) = @_;
    return if $rev == 0;
    my $fs = $repos->fs;
    my $parents = $fs->revision_prop ($rev, 'svk:parents');
    if (defined $parents) {
	$parents = [split /,/, $parents];
    }
    else {
	# Here, we use history traversal and limit the domain of
	# changes.  The domain grows if the change contains paths
	# outside the current domain.

	# XXX: doing so, we have to check more with those with svk:children
	my $leaf = $rev;
	while (1) {
	    --$leaf > 0 or last;
#	    warn "==> leaf is $leaf\n";
#	    my $root = $fs->revision_root ($leaf);
#	    my $anchor = anchor_in_change ($fs, $root);
#	    my $hist = $root->node_history ($anchor)->prev(0) or last;
#	    $leaf = ($hist->location)[1];
	    next if defined $fs->revision_prop ($leaf, 'svk:children');
	    push @$parents, $self->dependencies_in_tree ($repos, $rev, $leaf);
#	    last if $leaf == 0;

	}
	$parents ||= [];
	$fs->change_rev_prop ($rev, 'svk:parents', join(',',@$parents));
	for (@$parents) {
	    $fs->change_rev_prop ($_, 'svk:children',
				  join(',', $rev, split /,/, ($fs->revision_prop ($_, 'svk:children') || '')));
	}
    }
    return @$parents;
}

sub rev_depends_on {
    my ($self, $repos, $rev, $prev) = @_;
    my $xd = $self->{xd};
    Carp::confess unless $prev;
    my $txn = $repos->fs_begin_txn_for_commit ($prev-1, 'svk', 'not for commit');

    my $editor = SVK::Editor::Combiner->new
	($repos->get_commit_editor2 ($txn, '', '/', undef, undef, sub { }));
    my $fs = $repos->fs;

    local $@;
    eval {
	$xd->depot_delta ( oldroot => $fs->revision_root ($rev-1),
			   newroot => $fs->revision_root ($rev),
			   oldpath => ['/', ''],
			   newpath => '/',
			   editor => $editor,
			 );
    };
    $txn->abort;
    return $@ ? 1 : 0;
}

sub anchor_in_change {
    my ($fs, $root) = @_;
    my $changed = $root->paths_changed;
    my $anchor;
    for (keys %$changed) {
	unless (defined $anchor) {
	    $anchor = $_;
	    next;
	}
	while ($anchor ne '/' && index ("$_/","$anchor/") != 0) {
	    ($anchor) = get_depot_anchor (0, $anchor);
	}
    }
    return $anchor;
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
