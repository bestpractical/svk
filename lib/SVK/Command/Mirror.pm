package SVK::Command::Mirror;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Commit );

sub parse_arg {
    my ($self, @arg) = @_;
    return ($self->arg_depotpath ($arg[0]), $arg[1]);
}

sub run {
    my ($self, $target, $source) = @_;
    die "require SVN::Mirror" unless $self->svn_mirror;

    my $m = SVN::Mirror->new (target_path => $target->{path}, target => $target->{repospath},
			      pool => SVN::Pool->new, auth => $self->auth,
			      source => $source, target_create => 1);
    $m->init;
    return;
}

1;
