package SVK::Command::Resolved;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('R|recursive'	=> 'rec');
}

sub parse_arg {
    my ($self, @arg) = @_;

    return map {$self->arg_copath ($_)} @arg;
}

sub lock {
    my $self = shift;
    $self->lock_target ($_) for @_;
}

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	$self->{xd}->do_resolved ( %$target,
				   recursive => $self->{rec},
				 );
    }
    return;
}

1;

=head1 NAME

resolved - Mark checkout files or directories as resolved from conflict state.

=head1 SYNOPSIS

    resolved PATH...

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

