package SVK::Command::Sync;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::I18N;

sub options {
    ('s|skipto=s'	=> 'skip_to',
     'a|all'		=> 'sync_all',
     't|torev=s'	=> 'torev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return (@arg ? @arg : undef) if $self->{sync_all};

    return map {$self->arg_uri_maybe ($_)} @arg;
}

sub copy_notify {
    my ($self, $target, $m, undef, $path, $from_path, $from_rev) = @_;
    # XXX: on anchor, try to get a external copy cache
    return unless $m->path ne $path;
    return $target->depot->find_local_mirror($m->server_uuid, $from_path, $from_rev);
}

sub lock_message {
    my $target = shift;
    my $i = 0;
    sub {
	my ($mirror, $what, $who) = @_;
	print loc("Waiting for %1 lock on %2: %3.\n", $what, $target->depotpath, $who);
	if (++$i % 3 == 0) {
	    print loc ("
The mirror is currently locked. This might be because the mirror is
in the middle of a sensitive operation or because a process holding
the lock hung or died.  To check if the mirror lock is stalled,  see
if $who is a running, valid process

If the mirror lock is stalled, please interrupt this process and run:
    svk mirror --unlock %1
", $target->depotpath);
	}
    }
}

sub run {
    my ( $self, @arg ) = @_;

    die loc("argument skipto not allowed when multiple target specified")
        if $self->{skip_to} && ( $self->{sync_all} || $#arg > 0 );

    if ( $self->{sync_all} ) {
        local $@;
        my %arg = ( !defined( $arg[0] ) ? () : map { $_ => 1 } @arg );
        @arg = (
            defined( $arg[0] )
            ? @arg
            : sort keys %{ $self->{xd}{depotmap} } );
        my @newarg;
        foreach my $arg (@arg) {
	    my $path;
            my $orig_arg = $arg;
            ($arg, $path) = $arg =~ m{^/?([^/]*)/?(.*)?$};
            my ($depot) = eval { $self->{xd}->find_depot($arg) };
            unless ( defined $depot ) {
                if ( $arg =~ m{^/[^/]+/$} ) {
                    print loc( "%1 is not a valid depotname\n", $orig_arg );
                }
                else {
                    print loc( "%1 does not contain a valid depotname\n",
                        $orig_arg );
                }
                next;
            }

            my $arg_re     = qr{^\Q/$arg/$path\E};
            my @tempnewarg =
                map {
                ("/".$depot->depotname."$_") =~ /$arg_re/
                    ? $self->arg_depotpath("/".$depot->depotname."$_")
                    : ()
                } $depot->mirror->entries;

            if ( !@tempnewarg && $arg{$orig_arg} && ($path)  )
            {
                print loc( "no mirrors found underneath %1\n", $orig_arg );
                next;
            }
            push @newarg, @tempnewarg;
        }
        @arg = @newarg;
    }

    for my $target (@arg) {
        my $fs    = $target->repos->fs;
        my $m     = $target->depot->mirror->load_from_path($target->path_anchor) or next;

	my $run_sync = sub {
	    $m->sync_snapshot($self->{skip_to}) if $self->{skip_to};
	    $m->run( $self->{torev} );
	    1;
	};
        if ( $self->{sync_all} ) {
            print loc( "Starting to synchronize %1\n", $target->depotpath );
            eval { $run_sync->() };
            if ($@) {
                warn $@;
                last if ( $@ =~ /^Interrupted\.$/m );
            }
            next;
        }
        else {
	    $run_sync->();
        }
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Sync - Synchronize a mirrored depotpath

=head1 SYNOPSIS

 sync DEPOTPATH
 sync --all [DEPOTNAME|DEPOTPATH...]

=head1 OPTIONS

 -a [--all]             : synchronize all mirrored paths under
                          the DEPOTNAME/DEPOTPATH(s) provided
 -s [--skipto] REV      : start synchronization at revision REV
 -t [--torev] REV       : stop synchronization at revision REV

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
