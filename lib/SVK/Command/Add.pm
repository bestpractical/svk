package SVK::Command::Add;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('N|non-recursive'	=> 'nrec',
     'q|quiet'		=> 'quiet');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return $self->arg_condensed (@arg);
}

sub lock {
    $_[0]->lock_target ($_[1]);
}

sub run {
    my ($self, $target) = @_;

    $self->{xd}->do_add ( %$target,
			  recursive => !$self->{nrec},
			  quiet => $self->{quiet},
			);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Add - Put files and directories under version control

=head1 SYNOPSIS

 add [PATH...]

=head1 OPTIONS

 -N [--non-recursive]:   operate on single directory only

=head1 DESCRIPTION

Put files and directories under version control, scheduling
them for addition to repository.  They will be added in next commit.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
