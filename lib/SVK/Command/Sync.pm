package SVK::Command::Sync;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command::Commit );

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
    warn "copy_notify: ".join(',',@_);
}

sub run {
    my ($self, @arg) = @_;
    die "require SVN::Mirror" unless $self->svn_mirror;

    # XXX: support HEAD
    die "argument skipto not allowed when multiple target specified"
	if $self->{skip_to} && ($self->{sync_all} || $#arg > 0);

    if ($self->{sync_all}) {
	@arg = $self->parse_arg
	    (map {'/'.$_} map {SVN::Mirror::list_mirror ($_->{repos})} @arg);
    }

    for my $target (@arg) {
	my $m = SVN::Mirror->new (target_path => $target->{path},
				  target => $target->{repospath},
				  repos => $target->{repos},
				  pool => SVN::Pool->new, auth => $self->auth,
				  cb_copy_notify => \&copy_notify,
				  get_source => 1, skip_to => $self->{skip_to});
	$m->init ();
	$m->run ($self->{torev});
    }
    return;
}

1;

=head1 NAME

sync - synchronize a mirrored depotpath.

=head1 SYNOPSIS

    sync DEPOTPATH

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
