package SVK::View;

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(name revision txn root pool));

sub spec {
    my $self = shift;
    '/^'.$self->name.'@'.$self->revision;
}

1;
