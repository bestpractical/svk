package SVK::Resolve::GtkDiff;
use strict;
use base 'SVK::Resolve';
use File::Copy ();

sub arguments {
    my $self = shift;
    
    return (
        -o => $self->{merged},
        @{$self}{qw( yours theirs )}
    );
}

sub run_resolver {
    my $self = shift;
    unlink $self->{merged};
    return $self->SUPER::run_resolver(@_);
}


1;
