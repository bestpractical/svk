package SVK::Command::Resolved;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('R|recursive'	=> 'rec');
}

sub parse_arg {
    my ($self, @arg) = @_;

    return map {$self->arg_copath ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	SVK::XD::do_resolved ( $self->{info}, %$target,
			       recursive => $self->{rec},
			     );
    }
    return;
}

1;
