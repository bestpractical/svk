package SVK::Command::Help;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::I18N;

sub parse_arg { shift; @_ ? @_ : ''; }

sub run {
    my $self = shift;
    unless ($_[0]) {
	my @cmd;
	my $dir = $INC{'SVK/Command.pm'};
	$dir =~ s/\.pm$//;
	print loc("Available commands:\n");
	File::Find::find (sub {
			      push @cmd, $File::Find::name if m/\.pm$/;
			  }, $dir);
	$self->brief_usage ($_) for sort @cmd;
    } else {
        $self->get_cmd ($_)->usage(1) foreach @_;
    }
}

1;

__DATA__

=head1 NAME

SVK::Command::Help - Show help

=head1 SYNOPSIS

 help COMMAND

=head1 OPTIONS

 None

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
