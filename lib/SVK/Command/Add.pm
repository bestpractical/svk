package SVK::Command::Add;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('N|non-recursive'	=> 'nrec');
}

sub parse_arg {
    my ($self, @arg) = @_;

    return $self->arg_condensed (@arg);
}

sub run {
    my ($self, $target) = @_;

    SVK::XD::do_add ($self->{info},
		     %$target,
		     recursive => !$self->{nrec},
		    );
    return;
}

1;
