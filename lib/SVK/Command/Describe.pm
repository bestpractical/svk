package SVK::Command::Describe;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Diff SVK::Command::Log);
use SVK::XD;
use SVK::Editor::Diff;

sub options {
    ();
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    return ($arg[0], $self->arg_depotroot($arg[1]));
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $chg, $target) = @_;
    $self->{revspec} = $chg;
    $self->SVK::Command::Log::run ($target);
    $self->{revspec} = ($chg-1).":$chg";
    $self->SVK::Command::Diff::run ($target);
}

1;

__DATA__

=head1 NAME

SVK::Command::Describe - Describe a change

=head1 SYNOPSIS

 describe REV [DEPOTPATH | PATH]

=head1 DESCRIPTION

Displays the change in revision number I<REV> in the specified depot.
It always shows the entire change even if you specified a particular target.

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
