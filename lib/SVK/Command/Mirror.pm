package SVK::Command::Mirror;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;
use SVK::Util qw( HAS_SVN_MIRROR );

sub options {
    ('upgrade' => 'upgrade',
     'list'    => 'list');
}

sub parse_arg {
    my ($self, $path, @arg) = @_;

    # Allow "svk mi uri://... //depot" to mean "svk mi //depot uri://"
    if (@arg and $path =~ /^[A-Za-z][-+.A-Za-z0-9]*:/) {
	($arg[0], $path) = ($path, $arg[0]);
    }

    $path ||= '//';
    return ($self->arg_depotpath ($path), @arg);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target, $source, @options) = @_;
    die loc("cannot load SVN::Mirror") unless HAS_SVN_MIRROR;

    if ($self->{upgrade}) {
	SVN::Mirror::upgrade ($target->{repos});
	return;
    }
    elsif ($self->{list}) {
	my @paths = SVN::Mirror::list_mirror ($target->{repos});
	my $fs = $target->{repos}->fs;
	my $root = $fs->revision_root ($fs->youngest_rev);
	local $\ = "\n";
	my $fmt = "%-20s %-s\n";
	printf $fmt, 'Path', 'Source';
	print '=' x 60;
	my ($depot) = ($target->{depotpath} =~ /^(\/\w*)/);
	for (@paths) {
	    my $m = SVN::Mirror->new (target_path => $_, repos => $target->{repos},
				      get_source => 1);
	    printf $fmt, $depot.$_, $m->{source};
	}
	return;
    }

    my $m = SVN::Mirror->new (target_path => $target->{path},
			      source => $source,
			      repospath => $target->{repospath},
			      repos => $target->{repos},
			      options => \@options,
			      config => $self->{svnconfig},
			      pool => SVN::Pool->new,
			      # XXX: remove in next svn::mirror release
			      target => $target->{repospath},
			     );

    $m->init;
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Mirror - Initialize a mirrored depotpath

=head1 SYNOPSIS

 mirror [http|svn]://host/path DEPOTPATH
 mirror cvs::pserver:user@host:/cvsroot:module/... DEPOTPATH
 mirror p4:user@host:1666://path/... DEPOTPATH

 # You may also list the target part first:
 mirror DEPOTPATH [http|svn]://host/path

 mirror --list
 mirror --upgrade //
 mirror --upgrade /DEPOT/

=head1 OPTIONS

 --list                 : list mirrored paths
 --upgrade              : upgrade mirror state to the latest version

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
