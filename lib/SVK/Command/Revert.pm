package SVK::Command::Revert;
use strict;
our $VERSION = '0.13';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('R|recursive'	=> 'rec');
}

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_condensed (@arg);
}

sub lock {
    $_[0]->lock_target ($_[1]);
}

sub run {
    my ($self, $target) = @_;

    $self->{xd}->do_revert ( %$target,
			     recursive => $self->{rec},
			   );
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Revert - Revert changes made in checkout copies

=head1 SYNOPSIS

    revert PATH...

=head1 OPTIONS

  -R [--recursive]:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

