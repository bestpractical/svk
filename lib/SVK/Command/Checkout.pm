package SVK::Command::Checkout;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Update );
use SVK::XD;
use SVK::I18N;
use Cwd;
use File::Spec;

sub parse_arg {
    my ($self, @arg) = @_;
    my $depotpath = $self->arg_depotpath ($arg[0]);
    die loc("don't know where to checkout $arg[0]\n") unless $arg[1] || $depotpath->{path} ne '/';

    $arg[1] =~ s|/$|| if $arg[1];
    $arg[1] ||= (File::Spec->splitdir($depotpath->{path}))[-1];

    return ($depotpath, $arg[1]);
}

sub lock { $_[0]->{xd}->lock (Cwd::abs_path ($_[2])) }

sub run {
    my ($self, $target, $report) = @_;
    my $copath = Cwd::abs_path ($report);

    die loc("checkout path %1 already exists\n", $copath) if -e $copath;

    my ($entry, @where) = $self->{xd}{checkout}->get ($copath);
    die loc("overlapping checkout path not supported yet (%1)", $where[0])
	if exists $entry->{depotpath} && $#where > 0;

    $self->{xd}{checkout}->store_recursively ( $copath,
					       { depotpath => $target->{depotpath},
						 revision => 0,
						 '.schedule' => undef,
						 '.newprop' => undef,
						 '.deleted' => undef,
						 '.conflict' => undef,
					       });
    $self->{rev} = $target->{repos}->fs->youngest_rev unless defined $self->{rev};

    return $self->SUPER::run ($target->new (report => $report,
					    copath => $copath));
}

1;

__DATA__

=head1 NAME

SVK::Command::Checkout - Checkout the depotpath

=head1 SYNOPSIS

 checkout DEPOTPATH [PATH]

=head1 OPTIONS

 -r [--revision] rev:      revision

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
