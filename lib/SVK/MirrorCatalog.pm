package SVK::MirrorCatalog;
use strict;

use base 'Class::Accessor::Fast';
use SVK::Path;
use SVK::Mirror;
use SVK::Config;

__PACKAGE__->mk_accessors(qw(depot repos cb_lock revprop));

=head1 NAME

SVK::MirrorCatalog - mirror handling

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

# this is the cached and faster version of svn::mirror::has_local,
# which should be deprecated eventually.

my %mirror_cached;

sub entries {
    my $self = shift;
    my %mirrors = $self->_entries;
    return sort keys %mirrors;
}

sub _entries {
    my $self = shift;
    my $repos  = $self->repos;
    my $rev = $repos->fs->youngest_rev;
    delete $mirror_cached{$repos}
	unless ($mirror_cached{$repos}{rev} || -1) == $rev;
    return %{$mirror_cached{$repos}{hash}}
	if exists $mirror_cached{$repos};

    if ($repos->fs->revision_prop(0, 'svn:svnsync:from-url')) {
	$mirror_cached{$repos} = { rev => $rev, hash => { '/' => 1 } };
	return ( '/' => 1 );
    }

    my @mirrors = grep length,
        ( $repos->fs->revision_root($rev)->node_prop( '/', 'svm:mirror' )
            || '' ) =~ m/^(.*)$/mg;

    my %mirrored = map {
	local $@;
	eval {
            SVK::Mirror->load( { path => $_, depot => $self->depot, pool => SVN::Pool->new });
	    1;
	};
        $@ ? () : ($_ => 1)

    } @mirrors;

    $mirror_cached{$repos} = { rev => $rev, hash => \%mirrored};
    return %mirrored;
}

sub get {
    my ($self, $path) = @_;
    Carp::cluck if ref($path);
    return SVK::Mirror->load( { path => $path, depot => $self->depot, pool => SVN::Pool->new });
}

sub unlock {
    my ($self, $path) = @_;
    $self->get($path)->unlock('force');
}

sub is_mirrored {
    my ($self, $path) = @_;
    # XXX: check there's only one
    my ($mpath) = grep { SVK::Path->_to_pclass($_, 'Unix')->subsumes($path) } $self->entries;
    return unless $mpath;

    my $m = $self->get($mpath);
    $path =~ s/^\Q$mpath\E//;
    return wantarray ? ($m, $path) : $m;
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
