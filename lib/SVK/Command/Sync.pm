package SVK::Command::Sync;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;

sub options {
    ('s|skipto=s'	=> 'skip_to',
     'a|all'		=> 'sync_all',
     't|torev=s'	=> 'torev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('//') if $#arg < 0;
    return map {$self->arg_depotpath ($_)} @arg;
}

sub lock { $_[0]->lock_none }

sub copy_notify {
    my ($m, $path, $from_path, $from_rev) = @_;
    warn loc("copy_notify: %1", join(',',@_));
}

sub run {
    my ($self, @arg) = @_;
    die loc("cannot load SVN::Mirror") unless $self->svn_mirror;

    # XXX: support HEAD
    die loc("argument skipto not allowed when multiple target specified")
	if $self->{skip_to} && ($self->{sync_all} || $#arg > 0);

    if ($self->{sync_all}) {
	my @newarg;
	for (@arg) {
	    my ($depotname) = $self->{xd}->find_depotname ($_->{depotpath});
	    push @newarg, $self->parse_arg
		(map {"/$depotname$_"} SVN::Mirror::list_mirror ($_->{repos}));
	}
	@arg = @newarg;
    }

    for my $target (@arg) {
	my $m = SVN::Mirror->new (target_path => $target->{path},
				  target => $target->{repospath},
				  repos => $target->{repos},
				  pool => SVN::Pool->new, auth => $self->auth,
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

=head1 OPTIONS

 -a [--all]:           Needs description
 -t [--torev] arg:     Needs description
 -s [--skipto] arg:    Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
