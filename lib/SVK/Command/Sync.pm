package SVK::Command::Sync;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;
use SVK::Util qw( HAS_SVN_MIRROR );

sub options {
    ('s|skipto=s'	=> 'skip_to',
     'a|all'		=> 'sync_all',
     't|torev=s'	=> 'torev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return (@arg ? @arg : undef) if $self->{sync_all};
    @arg = ('//') if !@arg;
    return map {$self->arg_uri_maybe ($_)} @arg;
}

sub lock { $_[0]->lock_none }

sub copy_notify {
    my ($m, $path, $from_path, $from_rev) = @_;
    warn loc("copy_notify: %1", join(',',@_));
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
            my $target = eval { $self->arg_depotpath ("/$depot/") } or next;
	    push @newarg, (
                map {$self->arg_depotpath("/$depot$_")}
                    SVN::Mirror::list_mirror ($target->{repos})
            );
	}
        @arg = @newarg;
    }

    for my $target (@arg) {
	my $m = SVN::Mirror->new (target_path => $target->{path},
				  target => $target->{repospath},
				  repos => $target->{repos},
				  pool => SVN::Pool->new,
				  config => $self->{svnconfig},
				  cb_copy_notify => \&copy_notify,
				  revprop => ['svk:signature'],
				  get_source => 1, skip_to => $self->{skip_to});
	$m->init ();
	$m->run ($self->{torev});
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
 -s [--skipto] arg      : start synchronization at revision ARG
 -t [--torev] arg       : stop synchronization at revision ARG

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
