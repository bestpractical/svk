package SVK::Command::Mirror;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command::Commit );

sub parse_arg {
    my ($self, @arg) = @_;
    return ($self->arg_depotpath ($arg[0]), $arg[1]);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target, $source) = @_;
    die "require SVN::Mirror" unless $self->svn_mirror;

    my $m = SVN::Mirror->new (target_path => $target->{path}, target => $target->{repospath},
			      repos => $target->{repos},
			      pool => SVN::Pool->new, auth => $self->auth,
			      source => $source, target_create => 1);
    $m->init;
    return;
}

1;

=head1 NAME

mirror - Initialize a mirrored depotpath.

=head1 SYNOPSIS

    mirror DEPOTPATH SOURCEURL

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
