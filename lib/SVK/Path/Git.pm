package SVK::Path::Git;
use strict;
use base 'SVK::Accessor';

use base qw{ Class::Accessor::Fast };
use Git;

# a depot path object with git backend;
__PACKAGE__->mk_shared_accessors
    (qw(depot));

*path_anchor = __PACKAGE__->make_accessor('path');
__PACKAGE__->mk_clonable_accessors();
push @{__PACKAGE__->_clonable_accessors}, 'path_anchor';

for my $proxy (qw/depotname repospath/) {
    no strict 'refs';
    *{$proxy} = sub { my $self = shift; $self->depot; $self->depot->$proxy(@_) }
}

*path = *path_anchor;

#__PACKAGE__->mk_accessors(qw(path));

sub root {
    my $self = shift;
    require SVK::Root::Git;
    SVK::Root::Git->new({ depot => $self->depot, commit => 'HEAD' });
}


sub as_depotpath {
    return $_[0];
}

#sub path_anchor { $_[0]->path }

sub descend {
    my ($self, $entry) = @_;
    $self->path( $self->path . ( $self->path eq '/' ? $entry : "/$entry" ) );
    return $self;
}

sub path_target {
    return '';
}

sub seek_to {
    return $_[0];
}

sub revision {
    return 0;
}

sub repos {
    return $_[0];
}

sub fs {
    return $_[0];
}

sub youngest_rev {
    return 1;
}

sub depotpath {
    my $self = shift;

    Carp::cluck unless defined $self->depotname;

    return '/'.$self->depotname.$self->{path};
}

1;
