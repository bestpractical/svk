package SVK::Command::Checkout;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Update );
use SVK::XD;
use Cwd;
use File::Spec;

sub parse_arg {
    my ($self, @arg) = @_;
    my $depotpath = $self->arg_depotpath ($arg[0]);
    die "don't know where to checkout" unless $arg[1] || $depotpath->{path} ne '/';

    return ($depotpath,
	    $arg[1] = Cwd::abs_path ($arg[1] ||
				     (File::Spec->splitdir($depotpath->{path}))[-1]));

}

sub run {
    my ($self, $target, $copath) = @_;

    die "checkout path $copath already exists" if -e $copath;

    if (my ($entry, @where) = $self->{info}->{checkout}->get ($copath)) {
	die "overlapping checkout path not supported yet ($where[-1])"
	    if exists $entry->{depotpath} && $where[-1] ne $copath;
    }

    mkdir ($copath);
    $self->{info}->{checkout}->store_recursively ( $copath,
						   { depotpath => $target->{depotpath},
						     schedule => undef,
						     newprop => undef,
						     deleted => undef,
						     conflict => undef,
						     revision => 0,
						   });

    $self->{rev} = $target->{repos}->fs->youngest_rev unless defined $self->{rev};
    $target->{copath} = $copath;

    return $self->SUPER::run ($target);
}

1;
