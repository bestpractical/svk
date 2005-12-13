package SVK::Root::View;
use strict;
use warnings;

use base qw{ SVK::Root };

__PACKAGE__->mk_accessors(qw(view));

use Scalar::Util 'weaken';

sub txn_root {
    my ($self, $pool) = @_;
    my $newpool = SVN::Pool->new;
    my $txn = $self->fs->begin_txn
	( $self->txn->base_revision,
	  $newpool );

    $self->_apply_view_to_txn($txn, $self->view, $self->txn->base_revision);

    return $self->new({ txn => $txn, root => $txn->root($newpool), pool => $newpool });
}

sub revision_root {
    my ($self, $path, $rev, $pool) = @_;
    $path = $self->rename_check($path, $self->view->rename_map(''));
    return ( $self->root->fs->revision_root($rev, $pool),
	     $path );
}

# XXX: stolen from Editor::Rename, kill these
sub _path_inside {
    my ($path, $parent) = @_;
    return 1 if $path eq $parent;
    return substr ($path, 0, length ($parent)+1) eq "$parent/";
}

sub rename_check {
    my ($self, $path, $map) = @_;
    for (@$map) {
	my ($from, $to) = @$_;
	if (_path_inside ($path, $from)) {
	    my $newpath = $path;
	    $newpath =~ s/^\Q$from\E/$to/;
	    return $newpath;
	}
    }
    return $path;
}

sub new_from_view {
    my ($class, $txn, $view) = @_;
    my $pool = SVN::Pool->new;
    my $self = $class->new({ txn => $txn, root => $txn->root($pool),
			     view => $view, pool => $pool });
    weaken($self->{view});

    $self->_apply_view_to_txn($txn, $view, $view->revision);

    return $self;
}

sub _apply_view_to_txn {
    my ($self, $txn, $view, $revision) = @_;
    my $root = $txn->root($view->pool);
    for (@{$view->view_map}) {
	my ($path, $dest) = @$_;
	if (defined $dest) {
	    # XXX: mkpdir
	    SVN::Fs::copy ($root->fs->revision_root($revision), $dest,
			   $root, $path);
	}
	else {
	    $root->delete ($path);
	}
    }
    return;
}

1;
