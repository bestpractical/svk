package SVK::Path::Txn;
use strict;
use base 'SVK::Path';
__PACKAGE__->mk_accessors(qw(txn));

sub _get_inspector {
    my $self = shift;

    $self->txn($self->repos->fs_begin_txn_for_commit
	       ($self->repos->fs->youngest_rev,
		undef, undef, $self->pool))
	unless $self->txn;

    return SVK::Inspector::Root->new
       ({ root => $self->txn->root($self->pool),
	  istxn => 1,
          _pool => $self->pool,
          anchor => $self->{path} });
}

sub get_editor {
    my ($self, %arg) = @_;
    my $yrev = $self->repos->fs->youngest_rev;

    my $inspector = $self->inspector;

    my $callback;
    my ($editor, $post_handler) =
	$self->_commit_editor($self->txn, $callback, $self->pool);

    require SVK::Editor::Combiner;
    return (SVK::Editor::Combiner->new(_editor => [ $editor ]),
	    $inspector,
	    txn => $self->txn,
	    post_handler => $post_handler,
	    cb_rev => sub { $yrev },
	    cb_copyfrom =>
	    sub { ('file://'.$self->repospath.$_[0], $_[1]) });
}

1;
