package SVK::Command::Switch;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Update );
use SVK::XD;
use File::Spec;

sub parse_arg {
    my ($self, @arg) = @_;
    my $depotpath = $self->arg_depotpath ($arg[0]);
    return ($depotpath, $self->arg_copath ($arg[1] || ''));
}

sub run {
    my ($self, $target, $depotpath) = @_;

    die "different depot" unless $target->{repospath} eq $depotpath->{repospath};

    my ($entry, @where) = $self->{info}->{checkout}->get ($depotpath->{copath});

    die "can only switch checkout root" unless $where[-1] eq $depotpath->{copath};

    $self->{rev} = $target->{repos}->fs->youngest_rev unless defined $self->{rev};

    $depotpath->{target_path} = $target->{path};
    $self->SUPER::run ($depotpath);

    $self->{info}->{checkout}->store ($depotpath->{copath}, {depotpath => $target->{depotpath}});
    return;
}

1;
