package SVK::Command::Info;
use strict;
our $VERSION = '0.13';

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_copath ($_)} @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	my $rev = $target->{cinfo}{revision};
	print loc("Depot Path: %1\n", $target->{depotpath});
	print loc("Revision: %1\n", $rev);
	print loc(
	    "Last Changed Rev.: %1\n",
	    $target->{repos}->fs->revision_root($rev)->node_created_rev($target->{path})
	);
    }
}

1;

__DATA__

=head1 NAME

SVK::Command::Info - Display information about a file or directory

=head1 SYNOPSIS

    info [PATH]

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
