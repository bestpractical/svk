package SVK::Command::Smerge;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Merge );
use SVK::XD;

sub run {
    my ($self, @arg) = @_;
    $self->{auto}++;
    $self->SUPER::run (@arg);
}

1;
