package SVK::Command::Cleanup;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_copath ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;
    for (@arg) {
	if ($self->{info}{checkout}->get ($_->{copath})->{lock}) {
	    print "Cleanup stalled lock at $_->{copath}\n";
	    $self->{info}{checkout}->store ($_->{copath}, {lock => undef});
	}
	else {
	    print "$_->{copath} not locked\n";
	}
    }
    return;
}

1;

