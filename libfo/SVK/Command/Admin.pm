package SVK::Command::Admin;
use strict;
use SVK::I18N;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );

sub options {
    ();
}

sub parse_arg {
    my ($self, @arg) = @_;

    @arg or return;

    my $command = shift(@arg);
    return ($command, undef, @arg) if $command eq 'help';

    my $depot = '/'.(@arg ? pop(@arg) : '').'/';

    return ($command, $self->arg_depotroot($depot), @arg);
}

sub run {
    my ($self, $command, $target, @arg) = @_;

    if ($command eq 'rmcache') {
        my $dir = $self->{xd}->cache_directory;
        opendir my $fh, $dir or die loc("cannot open %1: %2", $dir, $!);
        unlink map "$dir/$_", readdir($fh);
        close $fh;
        return;
    }

    (system(
        'svnadmin',
        $command,
        ($target ? $target->{repospath} : ()),
        @arg
    ) >= 0) or die loc("Could not run %1: %2", 'svnadmin', $?);

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Admin - Administration tools

=head1 SYNOPSIS

Subcommands provided by F<svnadmin>:

 admin help [COMMAND]
 admin deltify [DEPOTNAME]
 admin dump [DEPOTNAME]
 admin hotcopy /path/to/repository [DEPOTNAME]
 admin list-dblogs [DEPOTNAME]
 admin list-unused-dblogs [DEPOTNAME]
 admin load [DEPOTNAME]
 admin lstxns [DEPOTNAME]
 admin recover [DEPOTNAME]
 admin rmtxns [DEPOTNAME]
 admin setlog -r REVISION FILE [DEPOTNAME]
 admin verify [DEPOTNAME]

Subcommands specific to F<svk>:

 admin rmcache

The C<rmcache> subcommand purges the inode/mtime/size cache on all checkout
subdirectories.  Use C<svk admin help> for helps on other subcommands.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
