package SVK::Command::Pull;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Update );
use SVK::XD;

sub options {
    ('a|all'		=> 'all',
     'l|lump'		=> 'lump');
}

sub parse_arg {
    my ($self, @arg) = @_;

    @arg = ('') if $#arg < 0;
    if ($self->{all}) {
        my $checkout = $self->{xd}{checkout}{hash};
        @arg = sort grep $checkout->{$_}{depotpath}, keys %$checkout;
    }

    $self->{lump} = 1; # -- XXX -- will break otherwise -- XXX ---

    $self->{sync}++;
    $self->{merge}++;
    $self->{incremental} = !$self->{lump};

    $self->SUPER::parse_arg (@arg);
}

1;

__DATA__

=head1 NAME

SVK::Command::Pull - Bring changes from another repository

=head1 SYNOPSIS

 pull [PATH...]

=head1 OPTIONS

 -a [--all]             : pull into all checkout paths
 -l [--lump]            : merge everything into a single commit log
                          (always enabled by default in this version)

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
