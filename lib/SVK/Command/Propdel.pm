package SVK::Command::Propdel;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Propset );
use SVK::XD;
use SVK::I18N;

sub parse_arg {
    my ($self, @arg) = @_;
    return if @arg < 1;
    push @arg, ('') if @arg == 1;
    return ($arg[0], map {$self->_arg_revprop ($_)} @arg[1..$#arg]);
}

sub lock {
    my $self = shift;
    $self->lock_target (@_[1..$#_]);
}

sub run {
    my ($self, $pname, @targets) = @_;
    $self->do_propset ($pname, undef, $_) for @targets;
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Propdel - Delete a property on files or dirs

=head1 SYNOPSIS

 propdel PROPNAME [DEPOTPATH | PATH...]

=head1 OPTIONS

 -R [--recursive]       : descend recursively
 -r [--revision] REV    : act on revision REV instead of the head revision
 --revprop              : operate on a revision property (use with -r)
 -m [--message] MESSAGE : specify commit message MESSAGE
 -F [--file] FILENAME   : read commit message from FILENAME
 --template             : use the specified message as the template to edit
 --encoding ENC         : treat -m/-F value as being in charset encoding ENC
 -P [--patch] NAME      : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -C [--check-only]      : try operation but make no changes
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
