package SVK::Command::Proplist;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('v|verbose'    => 'verbose',
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_co_maybe ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	my $rev = $self->{rev};
	$rev ||= $target->{repos}->fs->youngest_rev
	    unless $target->{copath};

	my $props = SVK::XD::do_proplist ($self->{info},
					  %$target,
					  rev => $rev,
					 );
	return unless %$props;
	my $report = $target->{copath} || $target->{depotpath};
	print "Properties on $report:\n";
	while (my ($key, $value) = each (%$props)) {
	    print "$key: $value\n";
	}
    }

    return;
}

1;
