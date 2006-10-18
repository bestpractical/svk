package SVK::Editor::Dynamic;
use strict;
use base 'SVK::Editor::Rename';

__PACKAGE__->mk_accessors(qw(root_rev _root_baton));

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    $self->_root_baton( $self->open_root( $self->root_rev ) );

    return $self;
}

sub adjust {
    $_[0]->adjust_last_anchor;
}

sub close_edit {
    my ($self, $editor) = @_;
    $self->close_directory( $self->_root_baton );
    $self->SUPER::close_edit;
}

1;
