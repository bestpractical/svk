package SVK::Command::Update;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('r|revision=i'  => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_copath ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	$self->{rev} = $target->{repos}->fs->youngest_rev
	    unless defined $self->{rev};

	SVK::XD::do_update ($self->{info},
			    %$target,
			    rev => $self->{rev},
			   );
    }
    return;
}

1;
