package SVK::Path::AccessorTransform;

use strict;
use warnings;

use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw(path_transforms));

sub push_path_transform {
    my $self = shift;
    my $transform = shift;
    unless (ref $transform eq 'CODE') {
        die "Path transformations must be code refs";
    }
    unshift @{$self->path_transforms}, $transform;
}

sub path_transform {
    my $self = shift;
    my $path = shift;
    
    return $path unless $self->path_transforms;
    
    for (@$self->path_tranasforms) {
        $path = $_->($path);
    }
    
    return $path;
}

1;