package SVK::Command::Info;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_copath ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	my $rev = $target->{cinfo}{revision};
	print "Depot Path: $target->{depotpath}\n";
	print "Revision: $rev\n";
	print "Last Changed Rev: ".$target->{repos}->fs->revision_root
	    ($rev)->node_created_rev ($target->{path})."\n";
    }
}

1;
