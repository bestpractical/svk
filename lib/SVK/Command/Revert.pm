package SVK::Command::Revert;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('R|recursive'	=> 'rec');
}

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_condensed (@arg);
}

sub run {
    my ($self, $target) = @_;

    SVK::XD::do_revert ( $self->{info},
			 %$target,
			 recursive => $self->{rec},
		       );
    return;
}

1;
