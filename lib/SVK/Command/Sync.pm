package SVK::Command::Sync;
use strict;
our $VERSION = '0.09';

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
				  pool => SVN::Pool->new, auth => $self->auth,
				  get_source => 1, skip_to => $self->{skip_to});
	$m->init ();
	$m->run ($self->{torev});
    }
    return;
}

1;
