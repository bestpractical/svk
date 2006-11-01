package SVK::Depot;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(repos repospath depotname));

=head1 NAME

SVK::Depot - Depot class in SVK

=head1 SYNOPSIS

=head1 DESCRIPTION

=over

=item mirror

Returns the mirror catalog object associated with the current depot.

=cut

sub mirror {
    my $self = shift;
    return SVK::MirrorCatalog->new
	( { repos => $self->repos,
            depot => $self,
	    revprop => ['svk:signature'] });
}

=item find_local_mirror($uuid, $path, [$rev])

Returns the path on the current depot that has the mirror of C<$uuid:$path>.
If C<$rev> is given, returns the local revision as well.

=cut

sub find_local_mirror {
    my ($self, $uuid, $path, $rev) = @_;
    my $myuuid = $self->repos->fs->get_uuid;
    return if $uuid eq $myuuid;

    my ($m, $mpath) = $self->_has_local("$uuid:$path");
    return ($m->path.$mpath,
	    $rev ? $m->find_local_rev($rev) : $rev) if $m;
    return;
}

sub _has_local {
    my ($self, $spec) = @_;
    for my $path ($self->mirror->entries) {
	my $m = $self->mirror->get($path);
	my $mspec = $m->spec;
	my $mpath = $spec;
	return ($m, '') if $mpath eq $mspec;
	next unless $mpath =~ s{^\Q$mspec\E/}{/};
	$mpath = '' if $mpath eq '/'; # XXX: why still need this?
	return ($m, $mpath);
    }
    return;
}

1;
