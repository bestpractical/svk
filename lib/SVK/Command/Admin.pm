package SVK::Command::Admin;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );

sub options {
    ();
}

sub parse_arg {
    my ($self, @arg) = @_;

    @arg or return;

    my $command = shift(@arg);
    return ($command, undef, @arg) if $command eq 'help';

    my $depot = (@arg ? shift(@arg) : '');

    return ($command, $self->arg_depotroot($depot), @arg);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $command, $target, @arg) = @_;
    system(
        'svnadmin',
        $command,
        ($target ? $target->{repospath} : ()),
        @arg
    );
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Admin - Administer a depot

=head1 SYNOPSIS

 admin help [COMMAND]
 admin deltify [DEPOTPATH]
 admin dump [DEPOTPATH]
 admin hotcopy [DEPOTPATH]
 admin list-dblogs [DEPOTPATH]
 admin list-unused-dblogs [DEPOTPATH]
 admin load [DEPOTPATH]
 admin lstxns [DEPOTPATH]
 admin recover [DEPOTPATH]
 admin rmtxns [DEPOTPATH]
 admin setlog [DEPOTPATH]
 admin verify [DEPOTPATH]

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
