package SVK::View;

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(base name revision txn root anchor view_map pool));

use Path::Class;

sub spec {
    my $self = shift;
    my $viewspec = $self->base->subdir($self->name)->relative('/');
    '/^'.$viewspec.'@'.$self->revision;
}

sub add_map {
    my ($self, $path, $dest) = @_;
    $self->view_map([]) unless $self->view_map;
    $self->adjust_anchor($dest) if defined $dest;
    push @{$self->view_map}, [$path, $dest];
}

sub adjust_anchor {
    my ($self, $dest) = @_;

    # XXX: Path::Class doesn't think '/' subsumes anything
    until ($self->anchor eq '/' or $self->anchor->subsumes($dest)) {
	$self->anchor($self->anchor->parent);
    }

}

sub rename_map {
    my ($self, $anchor) = @_;
    $anchor = $self->anchor unless defined $anchor;

    # return absolute map (without delets) with given anchor
    return [grep { defined $_->[1] } @{$self->view_map}] unless length $anchor;

    # return relative map
    return [map {
	defined $_->[1] ?
	    [ map {
		Path::Class::Dir->new_foreign('Unix', $_)->relative($anchor)
		} @$_ ] : ()
    } @{$self->view_map}];
}

1;
