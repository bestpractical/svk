package SVK::Command::Smerge;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command::Merge );
use SVK::XD;

sub run {
    my ($self, @arg) = @_;
    $self->{auto}++;
    $self->SUPER::run (@arg);
}

1;

=head1 NAME

smerge - Automatic merge all changes between branches.

=head1 SYNOPSIS

    smerge DEPOTPATH [PATH]
    smerge DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

    -m message:             commit message
    -C [--check-only]:      don't perform actual writes
    -l [--log]:             brings the logs of merged revs to the message buffer
    --no-ticket:            don't associate the ticket tracking merge history

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
