package SVK::Command::Cleanup;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command );

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_copath ($_)} @arg;
}

sub lock {
    my $self = shift;
    $self->lock_target ($_) for @_;
}

sub run {
    my ($self, @arg) = @_;
    for (@arg) {
	if ($self->{xd}{checkout}->get ($_->{copath})->{lock}) {
	    print "Cleanup stalled lock at $_->{copath}\n";
	    $self->{xd}{checkout}->store ($_->{copath}, {lock => undef});
	}
	else {
	    print "$_->{copath} not locked\n";
	}
    }
    return;
}

1;


=head1 NAME

cleanup - Cleanup stalled locks.

=head1 SYNOPSIS

    cleanup [PATH...]

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
