package SVK::Command::Resolved;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 0;
use SVK::XD;

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
				   recursive => $self->{recursive},
				 );
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Resolved - Remove conflict mark from checkout items

=head1 SYNOPSIS

 resolved PATH...

=head1 OPTIONS

 -R [--recursive]       : descend recursively

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

