package SVK::View;

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(base name revision anchor view_map pool));

use Path::Class;

sub spec {
    my $self = shift;
    # XXX: ->relative('/') is broken with File::Spec 3.14
    my $viewspec = $self->base->subdir($self->name);
    $viewspec =~ s{^/}{};
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
	($_->[1]->subsumes($anchor)) ?
	    [ map {
		Path::Class::Dir->new_foreign('Unix', $_)->relative($anchor)
		} @$_ ] : ()
    } grep { defined $_->[1] && $_->[0] ne $_->[1] } @{$self->view_map}];
}


sub rename_map2 {
    my ($self, $anchor, $actual_anchor) = @_;

    # return absolute map (without delets) with given anchor
    return [grep { defined $_->[1] } @{$self->view_map}] unless length $anchor;

    # return relative map
    return [map {
	($anchor ne $_->[0] && $anchor->subsumes($_->[0]) &&
	 $actual_anchor ne $_->[1] && $actual_anchor->subsumes($_->[1])) ?
	    [Path::Class::Dir->new_foreign('Unix', $_->[0])->relative($actual),
	     Path::Class::Dir->new_foreign('Unix', $_->[1])->relative($actual_anchor)]
	: ()
    } grep { defined $_->[1] && $_->[0] ne $_->[1] } @{$self->view_map}];

}

1;
