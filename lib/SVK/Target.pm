package SVK::Target;
use strict;
our $VERSION = $SVK::VERSION;
use SVK::XD;
use SVK::Util qw( get_anchor catfile abs2rel HAS_SVN_MIRROR IS_WIN32 );
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

=cut

sub same_repos {
    my ($self, @other) = @_;
    for (@other) {
	return 0 if $self->{repos} ne $_->{repos};
    }
    return 1;
}

=head2 same_source

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
    $self->{report} = catfile ($self->{report}, $entry);
    $self->{copath} = catfile ($self->{copath}, $entry);
}

=head2 universal

Returns corresponding L<SVK::Target::Universal> object.

=cut

sub universal {
    SVK::Target::Universal->new ($_[0]);
}

sub contains_copath {
    my ($self, $copath) = @_;
    foreach my $base (@{$self->{targets}}) {
	if ($copath ne abs2rel ($copath, $self->copath ($base))) {
	    return 1;
	}
    }
    return 0;
}

sub depotname {
    my $self = shift;

    $self->{depotpath} =~ m!^/([^/]*)!
      or die loc("'%1' does not contain a depot name.\n", $self->{depotpath});

    return $1;
}

sub copied_from {
    my ($self, $want_mirror) = @_;
    my $merge = SVK::Merge->new (%$self);

    # evil trick to take the first element from the array
    my @ancestors = $merge->copy_ancestors (@{$self}{qw( repos path revision )}, 1);
    while (my $ancestor = shift(@ancestors)) {
        shift(@ancestors);

        my $path = (split (/:/, $ancestor))[1];
        my $target = $self->new (
            path => $path,
            depotpath => '/' . $self->depotname . $path,
            revision => undef,
        );

        # make a depot path
        $target->as_depotpath;

        next if $target->root->check_path (
            $target->{path}
        ) == $SVN::Node::none;

        if ($want_mirror and HAS_SVN_MIRROR) {
            my ($m, $mpath) = SVN::Mirror::is_mirrored (
                $target->{repos},
                $target->{path}
            );
            $m->{source} or next;
        }

        return $target;
    }

    return undef;
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
