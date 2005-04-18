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
	print loc("Waiting for %1 lock on %2: %3.\n", $what, $target->{depotpath}, $who);
	if (++$i % 3 == 0) {
	    print loc ("
The mirror is currently locked. This might be because the mirror is
in the middle of a sensitive operation or because a process holding
the lock hung or died.  To check if the mirror lock is stalled,  see
if $who is a running, valid process

If the mirror lock is stalled, please interrupt this process and run:
    svk mirror --unlock %1
", $target->{depotpath});
	}
    }
}

sub run {
    my ($self, @arg) = @_;
    die loc("cannot load SVN::Mirror") unless HAS_SVN_MIRROR;

    die loc("argument skipto not allowed when multiple target specified")
	if $self->{skip_to} && ($self->{sync_all} || $#arg > 0);

    if ($self->{sync_all}) {
	local $@;
	@arg = (defined($arg[0]) ? @arg : sort keys %{$self->{xd}{depotmap}});
        my @newarg;
        foreach my $depot (@arg) {
            $depot =~ s{/}{}g;
            my $target = eval { $self->arg_depotpath ("/$depot/") };
	    unless ($target) {
		print $@;
		next;
	    }
	    push @newarg, (
                map {$self->arg_depotpath("/$depot$_")}
                    SVN::Mirror::list_mirror ($target->{repos})
            );
	}
        @arg = @newarg;
    }

    for my $target (@arg) {
	my $repos = $target->{repos};
	my $fs = $repos->fs;
	my $m = SVN::Mirror->new (target_path => $target->{path},
				  target => $target->{repospath},
				  repos => $repos,
				  pool => SVN::Pool->new,
				  config => $self->{svnconfig},
				  cb_copy_notify => sub { $self->copy_notify (@_) },
				  lock_message => lock_message($target),
				  revprop => ['svk:signature'],
				  get_source => 1, skip_to => $self->{skip_to});
	$m->init ();

        if ($self->{sync_all}) {
            print loc("Starting to synchronize %1\n", $target->{depotpath});
            eval { $m->run ($self->{torev});
		   find_prev_copy ($fs, $fs->youngest_rev);
		   1 } or warn $@;
            next;
        }
        else {
            $m->run ($self->{torev});
	    # build the copy cache after sync.
	    # we should do this in svn::mirror::committed, with a
	    # hook provided here.
	    find_prev_copy ($fs, $fs->youngest_rev);
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
 sync --all [DEPOTNAME...]

=head1 OPTIONS

 -a [--all]             : synchronize all mirrored paths
 -s [--skipto] REV	: start synchronization at revision REV
 -t [--torev] REV	: stop synchronization at revision REV

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
