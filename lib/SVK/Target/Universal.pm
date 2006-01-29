package SVK::Target::Universal;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use SVK::Util qw(find_svm_source find_local_mirror);
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(uuid path rev));

=head1 NAME

SVK::Target::Universal - svk target that might not be local

=head1 SYNOPSIS

 $target = SVK::Target::Universal->new ($uuid, $path, $rev);
 $target = SVK::Target::Universal->new ($local_target);
 $local_target = $target->local ($xd, 'depot');

=cut

sub new {
    my $class = shift;
    return $class->new (find_svm_source ($_[0]->repos, $_[0]->path, $_[0]->revision))
	if ref ($_[0]);

    my ($uuid, $path, $rev) = @_;
    bless { uuid => $uuid,
	    path => $path,
	    rev => $rev }, $class;
}

sub local {
    my $self = shift;
    my ($repospath, $repos, $depot, $xd);
    if ($#_) {
	($xd, $depot) = @_;
	($repospath, undef, $repos) = $xd->find_repos ("/$depot/", 1);
    }
    else {
	$repos = $_[0];
	$repospath = $repos->path;
    }

    my ($path, $rev) = $self->{uuid} ne $repos->fs->get_uuid ?
	find_local_mirror ($repos, @{$self}{qw/uuid path rev/}) :
	@{$self}{qw/path rev/};

    # $rev can be undefined even if $path is defined.  This is the case
    # that you have a out-of-date mirror of something with a newer merge
    # ticket
    return unless defined $path && defined $rev;

    SVK::Path->real_new
	({ repos => $repos,
	   mirror => $xd ? $xd->mirror($repos) : undef,
	   repospath => $repospath,
	   path => $path, # XXX: use path_anchor accessor
	   revision => $rev,
	   depotname => $depot || '',
	 });
}

sub same_resource {
    my ($self, $other) = @_;
    return ($self->uuid eq $other->uuid && $self->path eq $other->path);
}

sub ukey {
    my $self = shift;
    return join(':', $self->uuid, $self->path);
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
