package SVK::Path::Txn;
use base 'SVK::Path';
__PACKAGE__->mk_accessors(qw(txn pool));

sub get_editor {
    my ($self, %arg) = @_;

    $self->pool(SVN::Pool->new) unless $self->pool;
    my $yrev = $self->repos->fs->youngest_rev;
    $self->txn($self->repos->fs_begin_txn_for_commit
	       ($yrev, $arg{author}, $arg{message}, $self->pool))
	unless $self->txn;

    my $inspector = SVK::Inspector::Root->new
	({ root => $self->txn->root,
	   anchor => $self->{path},
	   base_rev => $yrev });

    my ($editor, $post_handler) =
	$self->_commit_editor($self->txn, $callback, $self->pool);

    require SVK::Editor::Combiner;
    return (SVK::Editor::Combiner->new(_editor => [ $editor ]),
	    $inspector,
	    txn => $txn,
	    post_handler => $post_handler,
	    cb_rev => sub { $yrev },
	    cb_copyfrom =>
	    sub { ('file://'.$self->repospath.$_[0], $_[1]) });
}

1;

