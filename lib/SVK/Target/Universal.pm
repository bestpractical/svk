package SVK::Target::Universal;
use strict;
our $VERSION = $SVK::VERSION;
use SVK::Util qw(find_svm_source find_local_mirror);

=head1 NAME

SVK::Target::Universal - svk target that might not be local

=head1 SYNOPSIS

 $target = SVK::Target::Universal->new ($uuid, $path, $rev);
 $target = SVK::Target::Universal->new ($local_target);
 $local_target = $target->local ($xd, 'depot');

=cut

sub new {
    my $class = shift;
    return $class->new (find_svm_source ($_[0]->{repos}, $_[0]->path, $_[0]->{revision}))
	if ref ($_[0]);

    my ($uuid, $path, $rev) = @_;
    bless { uuid => $uuid,
	    path => $path,
	    rev => $rev }, $class;
}

sub local {
    my ($self, $xd, $depot) = @_;
    my ($repospath, undef, $repos) = $xd->find_repos ("/$depot/", 1);

    my ($path, $rev) = $self->{uuid} ne $repos->fs->get_uuid ?
	find_local_mirror ($repos, @{$self}{qw/uuid path rev/}) :
	@{$self}{qw/path rev/};

    return unless $path;

    SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  path => $path,
	  revision => $rev,
	  depotpath => "/$depot$path"
	);
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
