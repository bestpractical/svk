package SVK::View;

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(base name revision txn root rename_map pool));

sub spec {
    my $self = shift;
    my $viewspec = $self->base->subdir($self->name)->relative('/');
    '/^'.$viewspec.'@'.$self->revision;
}

sub add_map {
    my $self = shift;
    $self->rename_map([]) unless $self->rename_map;
    push @{$self->rename_map}, [@_];
}


1;
