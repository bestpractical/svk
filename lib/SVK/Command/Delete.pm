package SVK::Command::Delete;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;

sub parse_arg {
    my ($self, @arg) = @_;
    return $self->arg_condensed (@arg);
}

sub run {
    my ($self, $target) = @_;

    SVK::XD::do_delete ( $self->{info},
			 %$target,
		       );

    return;
}

1;
