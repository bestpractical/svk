package SVK::Command::Switch;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command::Update );
use SVK::XD;
use SVK::I18N;
use File::Spec;

sub parse_arg {
    my ($self, @arg) = @_;
    $self->usage if $#arg < 0 || $#arg > 1;
    my $depotpath = $self->arg_depotpath ($arg[0]);
    return ($depotpath, $self->arg_copath ($arg[1] || ''));
}

sub lock { $_[0]->lock_target ($_[2]) }

sub run {
    my ($self, $target, $depotpath) = @_;

    die loc("different depot") unless $target->{repospath} eq $depotpath->{repospath};

    my ($entry, @where) = $self->{xd}{checkout}->get ($depotpath->{copath});

    die loc("can only switch checkout root") unless $where[0] eq $depotpath->{copath};

    $self->{rev} = $target->{repos}->fs->youngest_rev unless defined $self->{rev};

    # XXX: check relation between target_path and path
    $depotpath->{target_path} = $target->{path};
    $self->SUPER::run ($depotpath);

    $self->{xd}{checkout}->store ($depotpath->{copath}, {depotpath => $target->{depotpath}});
    return;
}

1;

=head1 NAME

SVK::Command::Switch - Switch to another branch and keep local modifications

=head1 SYNOPSIS

    switch DEPOTPATH [PATH]

=head1 OPTIONS

    -r [--revision]:      revision

=head1 OPTIONS

  -r [--revision] arg:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
