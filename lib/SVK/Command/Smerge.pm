package SVK::Command::Smerge;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Merge );
use SVK::XD;

sub options {
    ($_[0]->SUPER::options,
     'B|baseless'	=> 'baseless',
     'b|base:i'		=> 'base',
    );
}

sub run {
    my ($self, @arg) = @_;
    $self->{auto}++;
    $self->SUPER::run (@arg);
}

1;

__DATA__

=head1 NAME

SVK::Command::Smerge - Automatic merge all changes between branches

=head1 SYNOPSIS

 smerge DEPOTPATH [PATH]
 smerge DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

 -m [--message] message:    commit message
 -C [--check-only]:         don't perform actual writes
 -l [--log]:                brings the logs of merged revs to the message buffer
 --remoterev:               Use remote revision in merge log
 --host host:               Use host as hostname shown in merge log
 --no-ticket:               don't associate the ticket tracking merge history
 -B [--baseless]:           use the oldest revision as the merge point
 -b [--base] rev:           manually specify source revision as the merge point
 --force:                   Needs description
 -s [--sign]:               Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
