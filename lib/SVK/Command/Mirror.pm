package SVK::Command::Mirror;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;

sub parse_arg {
    my ($self, $path, @arg) = @_;
    return ($self->arg_depotpath ($path), @arg);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target, $source, @options) = @_;
    die loc("cannot load SVN::Mirror") unless $self->svn_mirror;

    my $m = SVN::Mirror->new (target_path => $target->{path},
			      source => $source,
			      repospath => $target->{repospath},
			      repos => $target->{repos},
			      options => \@options,
			      pool => SVN::Pool->new, auth => $self->auth,
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

    mirror DEPOTPATH [http|svn]://server.host/path
    mirror DEPOTPATH cvs::pserver:user@host:/cvsroot:module/...
    mirror DEPOTPATH p4:user@host:1666://depot/module/...

=head1 DESCRIPTION

=head1 OPTIONS

  -m [--message] arg:	Needs description
  -C [--check-only]:	Needs description
  -s [--sign]:	Needs description
  --force:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
