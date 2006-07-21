package SVK::Mirror;
use strict;

use base 'Class::Accessor::Fast';
use SVK::Util qw( HAS_SVN_MIRROR );
use SVK::Path;

__PACKAGE__->mk_accessors(qw(repos cb_lock config revprop));

=head1 NAME

SVK::Mirror - mirror handling

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

# this is the cached and faster version of svn::mirror::has_local,
# which should be deprecated eventually.

my %mirror_cached;

sub entries {
    my $self = shift;
    return unless HAS_SVN_MIRROR;
    my $repos  = $self->repos;
    my $rev = $repos->fs->youngest_rev;
    delete $mirror_cached{$repos}
	unless ($mirror_cached{$repos}{rev} || -1) == $rev;
    return %{$mirror_cached{$repos}{hash}}
	if exists $mirror_cached{$repos};
    my %mirrored = map {
	my $m;
	local $@;
	eval {
	    $m = $self->svnmirror_object( $_, get_source => 1);
	    $m->init;
	    1;
	};
	$@ ? () : ($_ => SVK::Mirror::Entry->new({mirror => $m}))
    } SVN::Mirror::list_mirror($repos);

    $mirror_cached{$repos} = { rev => $rev, hash => \%mirrored};
    return %mirrored;
}

sub svnmirror_object {
    my ($self, $path, %arg) = @_;
    SVN::Mirror->new
	( target_path    => $path,
	  repos          => $self->repos,
	  config         => $self->config,
	  revprop        => $self->revprop,
	  pool           => SVN::Pool->new,
	  %arg);
}

sub load_from_path {
    my ($self, $path) = @_;
    my $m = $self->svnmirror_object
	( $path,  get_source => 1 );
    $m->init;
    return SVK::Mirror::Entry->new({ mirror => $m });
}

sub add_entry {
    my ($self, $path, $source, @options) = @_;
    my $m = $self->svnmirror_object
	( $path, source => $source, options => \@options );
    $m->init;
}

sub unlock {
    my ($self, $path) = @_;
    my $m = $self->svnmirror_object
	( $path,  get_source => 1, ignore_lock => 1 );
    $m->init;
    $m->unlock('force')
}

sub is_mirrored {
    my ($self, $path) = @_;
    my %mirrors = $self->entries;
    # XXX: check there's only one
    my ($mpath) = grep { SVK::Path->_to_pclass($_, 'Unix')->subsumes($path) }
	keys %mirrors;
    return unless $mpath;

    my $m = $mirrors{$mpath}->mirror;
    $path =~ s/^\Q$mpath\E//;
    return wantarray ? ($m, $path) : $m;
}

package SVK::Mirror::Entry;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(mirror));

sub sync {
    my ($self, %arg) = @_;
    $self->mirror->{$_} = $arg{$_} for keys %arg;
    $self->mirror->run($arg{torev});
}

sub spec {
    my $self = shift;
    my $m = $self->mirror;
    return join(':', $m->{source_uuid}, $m->{source_path});
}

=head1 SEE ALSO

L<SVN::Mirror>

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
