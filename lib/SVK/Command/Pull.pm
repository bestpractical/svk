package SVK::Command::Pull;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Update );
use SVK::XD;

sub options {
   ('a|all'		=> 'all',
    'force-incremental' => 'force_incremental',
    'l|lump'		=> 'lump');
}

sub parse_arg {
    my ($self, @arg) = @_;

    @arg = ('') if $#arg < 0;

    # -- XXX -- will break otherwise -- XXX ---
    # (Possibly fixed now, so we'll add an undocumented option to override
    # this, to enable testing.)
    $self->{lump} = 1 unless $self->{force_incremental};
    $self->{incremental} = !$self->{lump};

    if ($self->{all}) {
        my $checkout = $self->{xd}{checkout}{hash};
        @arg = sort grep $checkout->{$_}{depotpath}, keys %$checkout;
    } 
    elsif ( @arg == 1 and !$self->arg_co_maybe($arg[0])->isa('SVK::Path::Checkout')) {
        # If the last argument is a depot path, rather than a copath
        # then we should do a merge to the local depot, rather than 
        # an update to the path
        return $self->rebless (
            smerge => {
                to => 1,
                log => 1,
                message => '',
            }
        )->parse_arg (@arg);
    }


    $self->{sync}++;
    $self->{merge}++;

    $self->SUPER::parse_arg (@arg);
}

1;

__DATA__

=head1 NAME

SVK::Command::Pull - Bring changes from another repository

=head1 SYNOPSIS

 pull [PATH...]

    Update your local branch and checkout path from the remote
    master repository.

 pull DEPOTPATH

    Update your local branch from the remote master repository.

=head1 OPTIONS

 -a [--all]             : pull into all checkout paths
 -l [--lump]            : merge everything into a single commit log
                          (always enabled by default for now)

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
