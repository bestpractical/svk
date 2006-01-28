package SVK::Inspector::Compat;

use strict;
use warnings;
use base qw{Class::Accessor};

my @CALLBACKS = qw{cb_exist cb_localprop cb_localmod};

__PACKAGE__->mk_accessors(@CALLBACKS);


sub exist {
        my $self = shift;
        $self->cb_exist->(@_);
}

sub localprop {
        my $self = shift;
        $self->cb_localprop->(@_);
}

sub localmod {
        my $self = shift;
        return $self->cb_localmod->(@_);
}


1;