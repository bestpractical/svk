package SVK::Command::Push;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Smerge );
use SVK::XD;

sub options {
    ('f|from=s'         => 'from_path',
     'l|lump'           => 'lump',
     'C|check-only'     => 'check_only',
     'S|sign'	        => 'sign',
     'P|patch=s'        => 'patch',
     'verbatim'		=> 'verbatim',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;

    if (!$self->{from_path}) {
        $self->{from}++;
    }
    else {
        unshift @arg, $self->{from_path};
    }

    # "svk push -P" has the same effect as "svk push -l",
    # because incremental patches is not yet implemented.
    if ($self->{lump} or $self->{patch}) {
        $self->{log}++;
        $self->{message} = '';
        delete $self->{incremental};
    }
    else {
        $self->{incremental}++;
    }

    $self->SUPER::parse_arg (@arg);
}

1;

__DATA__

=head1 NAME

SVK::Command::Push - Move changes into another repository

=head1 SYNOPSIS

 push [DEPOTPATH | PATH]

=head1 OPTIONS

 -f [--from] arg        : push from the specified path
 -l [--lump]            : merge everything into a single commit log
 -C [--check-only]      : try operation but make no changes
 -P [--patch] arg       : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 --verbatim             : verbatim merge log without indents and header

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
