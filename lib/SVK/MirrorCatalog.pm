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
    my $repos  = $self->repos;
    my $rev = $repos->fs->youngest_rev;
    delete $mirror_cached{$repos}
	unless ($mirror_cached{$repos}{rev} || -1) == $rev;
    return %{$mirror_cached{$repos}{hash}}
	if exists $mirror_cached{$repos};
    my @mirrors
        = ( $repos->fs->revision_root($rev)->node_prop( '/', 'svm:mirror' )
            || '' ) =~ m/^(.*)$/mg;

    my %mirrored = map {
	my $m;
	local $@;
	eval {
            $m = SVK::Mirror->load( { path => $_, depot => $self->depot, pool => SVN::Pool->new });
	    1;
	};
        $@ ? () : ($_ => $m)

    } @mirrors;

    $mirror_cached{$repos} = { rev => $rev, hash => \%mirrored};
    return %mirrored;
}

sub load_from_path { # DEPRECATED: only used by ::Command::Sync
    my ($self, $path) = @_;

    my %mirrors = $self->entries;
    return $mirrors{$path};
}

sub unlock {
    my ($self, $path) = @_;
    my %mirrors = $self->entries;
    $mirrors{$path}->unlock('force');
}

sub is_mirrored {
    my ($self, $path) = @_;
    my %mirrors = $self->entries;
    # XXX: check there's only one
    my ($mpath) = grep { SVK::Path->_to_pclass($_, 'Unix')->subsumes($path) }
	keys %mirrors;
    return unless $mpath;

    my $m = $mirrors{$mpath};
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
