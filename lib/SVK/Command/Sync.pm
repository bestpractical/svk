package SVK::Command::Sync;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::I18N;
use SVK::Util qw( HAS_SVN_MIRROR find_prev_copy find_local_mirror );

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
    my ($self, $m, $path, $from_path, $from_rev) = @_;
    # XXX: on anchor, try to get a external copy cache
    return unless $m->{target_path} ne $path;
    return find_local_mirror ($m->{repos}, $m->{rsource_uuid}, $from_path, $from_rev);
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
    die loc("cannot load SVN::Mirror") unless HAS_SVN_MIRROR;

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
            my $orig_arg = $arg;
            $arg = "/$arg/" if $arg !~ m{/};
            $arg = "$arg/" unless $arg =~ m{/$};

            my ($depot) = eval { $self->arg_depotname($arg) };
            unless ( defined $depot ) {
                if ( $arg =~ m{^/[^/]+/$} ) {
                    print loc( "%1 is not a valid depotname\n", $arg );
                }
                else {
                    print loc( "%1 does not contain a valid depotname\n",
                        $arg );
                }
                next;
            }

            my $target = eval { $self->arg_depotpath($arg) };
            unless ($target) {
                print $@;
                next;
            }

            my $arg_re     = qr/^\Q$arg\E/;
            my @tempnewarg =
                map {
                "/$depot$_/" =~ /$arg_re/
                    ? $self->arg_depotpath("/$depot$_")
                    : ()
                } SVN::Mirror::list_mirror( $target->repos );

            unless ( @tempnewarg
                || !exists $arg{$orig_arg}
                || $arg =~ m{^/[^/]*/$} )
            {
                print loc( "no mirrors found underneath %1\n", $arg );
                next;
            }
            push @newarg, @tempnewarg;
        }
        @arg = @newarg;
    }

    for my $target (@arg) {
        my $repos = $target->repos;
        my $fs    = $repos->fs;
        my $m     = $self->{xd}->mirror($repos)
	    ->load_from_path($target->path_anchor);

	my $run_sync = sub {
	    $m->sync( torev => $self->{torev}, skip_to => $self->{skip_to},
		      cb_copy_notify => sub { $self->copy_notify(@_) },
		      lock_message   => lock_message($target));
	    find_prev_copy( $fs, $fs->youngest_rev );
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
            # build the copy cache after sync.
            # we should do this in svn::mirror::committed, with a
            # hook provided here.
            find_prev_copy( $fs, $fs->youngest_rev );
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
