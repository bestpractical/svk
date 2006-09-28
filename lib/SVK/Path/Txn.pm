package SVK::Path::Txn;
use strict;
use base 'SVK::Path';
__PACKAGE__->mk_shared_accessors(qw(txn));

sub _get_inspector {
    my $self = shift;

    Carp::cluck unless $self->repos;
    $self->txn($self->repos->fs_begin_txn_for_commit
	       ($self->revision,
		undef, undef, $self->pool))
	unless $self->txn;

    return SVK::Inspector::Root->new
       ({ root => $self->txn->root($self->pool),
	  istxn => 1,
          _pool => $self->pool,
          anchor => $self->path_anchor });
}

sub get_editor {
    my ($self, %arg) = @_;
    my $inspector = $self->inspector;

    my $callback;
    my ($editor, $post_handler) =
	$self->_commit_editor($self->txn, $callback, $self->pool);

    require SVK::Editor::Combiner;
    return (SVK::Editor::Combiner->new(_editor => [ $editor ]),
	    $inspector,
	    txn => $self->txn,
	    post_handler => $post_handler,
	    cb_rev => sub { $self->revision },
	    cb_copyfrom => sub { $self->as_url(1, @_) });
}

sub root {
    my $self = shift;
    return $self->inspector->root;
}

sub as_depotpath {
    my $self = shift;
    my $depotpath = $self->mclone(txn => undef);
    bless $depotpath, 'SVK::Path';
    return $depotpath;
}

sub prev {
    my ($self) = shift;
    $self->as_depotpath;
}

1;
