package SVK::Command::Help;
use strict;
our $VERSION = '0.12';

use base qw( SVK::Command );
use SVK::I18N;

sub run {
    my $self = shift;
    my ($cmd) = @_;
    unless ($cmd) {
	my @cmd;
	my $dir = $INC{'SVK/Command.pm'};
	$dir =~ s/\.pm$//;
	print loc("Available commands:\n");
	File::Find::find (sub {
			      push @cmd, $File::Find::name if m/\.pm$/;
			  }, $dir);
	$self->brief_usage ($_) for sort @cmd;
    } else {
        $self->get_cmd ($cmd)->usage(1);
    }
}

1;

=head1 NAME

SVK::Command::Help - Show help

=head1 SYNOPSIS

    help command

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
