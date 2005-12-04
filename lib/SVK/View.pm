package SVK::View;

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(name revision txn root rename_map pool));

sub spec {
    my $self = shift;
    '/^'.$self->name.'@'.$self->revision;
}

sub add_map {
    my $self = shift;
    $self->rename_map([]) unless $self->rename_map;
    push @{$self->rename_map}, [@_];
}


1;
