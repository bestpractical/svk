package SVK::Command::Cleanup;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::I18N;

sub options {
    ('a|all' => 'all');
}

sub parse_arg {
    my ($self, @arg) = @_;
    ++$self->{hold_giant};
    return undef if $self->{all};
    @arg = ('') if $#arg < 0;
    return map {$self->arg_copath ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;

    if ($self->{all}) {
        $self->{xd}{checkout}->store_recursively ('', {lock => undef});
        print loc("Cleaned up all stalled locks.\n");
        return;
    }

    for (@arg) {
	if ($self->{xd}{checkout}->get ($_->{copath})->{lock}) {
	    print loc("Cleaned up stalled lock on %1.\n", $_->{copath});
	    $self->{xd}{checkout}->store ($_->{copath}, {lock => undef});
	}
        else {
	    print loc("Path %1 was not locked.\n", $_->{copath});
	}
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Cleanup - Remove stalled locks

=head1 SYNOPSIS

 cleanup [PATH...]

=head1 OPTIONS

 -a [--all]             : remove all stalled locks

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
