package SVK::Resolve::Meld;
use strict;
use base 'SVK::Resolve';
use File::Copy ();

sub arguments {
    my $self = shift;

    File::Copy::copy($self->{base} => $self->{merged});
    return (@{$self}{qw( yours merged theirs )});
}

1;
