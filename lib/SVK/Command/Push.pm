package SVK::Command::Push;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Smerge );
use SVK::XD;

sub options {
    ('f|from=s'         => 'from_path',
     'l|lump'           => 'lump',
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

    if ($self->{lump}) {
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

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
