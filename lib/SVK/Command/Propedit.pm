package SVK::Command::Propedit;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Propset );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw(get_buffer_from_editor);

sub parse_arg {
    my ($self, @arg) = @_;
    return unless $#arg == 1;
    return ($arg[0], $self->arg_co_maybe ($arg[1]));
}

sub lock {
    my $self = shift;
    $_[1]->{copath} ? $self->lock_target ($_[1]) : $self->lock_none;
}

sub run {
    my ($self, $pname, $target) = @_;

    my $pvalue = $self->{xd}->do_proplist ($target)->{$pname};
    $pvalue = get_buffer_from_editor (loc("property %1", $pname), undef, $pvalue || '',
				      'prop');

    $self->do_propset ($pname, $pvalue, $target);

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Propedit - Edit a property on path

=head1 SYNOPSIS

 propedit PROPNAME [PATH|DEPOTPATH...]

=head1 OPTIONS

 -m [--message] arg     : specify commit message ARG
 -C [--check-only]      : try operation but make no changes
 -s [--sign]            : sign this change

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
