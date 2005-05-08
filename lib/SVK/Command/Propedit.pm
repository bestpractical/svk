package SVK::Command::Propedit;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Propset );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw(get_buffer_from_editor);

sub parse_arg {
    my ($self, @arg) = @_;
    return if @arg < 1 or @arg > 2;
    push @arg, ('') if @arg == 1;
    return ($arg[0], $self->_arg_revprop ($arg[1]));
}

sub lock {
    my $self = shift;
    $self->lock_target ($_[1]);
}

sub run {
    my ($self, $pname, $target) = @_;

    my $pvalue = $self->_proplist ($target)->{$pname};

    $pvalue = get_buffer_from_editor (
        loc("property %1", $pname),
        undef,
        (defined($pvalue) ? $pvalue : ''),
        'prop'
    );

    $self->do_propset ($pname, $pvalue, $target);

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Propedit - Edit a property on path

=head1 SYNOPSIS

 propedit PROPNAME [DEPOTPATH | PATH...]

=head1 OPTIONS

 -m [--message] MESSAGE	: specify commit message MESSAGE
 -F [--file] FILENAME	: read commit message from FILENAME
 -C [--check-only]      : try operation but make no changes
 -R [--recursive]       : descend recursively
 -r [--revision] REV	: act on revision REV instead of the head revision
 -P [--patch] NAME	: instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 --revprop              : operate on a revision property (use with -r)
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
