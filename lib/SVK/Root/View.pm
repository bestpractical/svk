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

    return $self->new({ view => $self->view, txn => $txn,
			root => $txn->root($newpool), pool => $newpool });
}

sub get_revision_root {
    my ($self, $path, $rev, $pool) = @_;
    $path = $self->rename_check($path, $self->view->rename_map(''));
    return ( SVK::Root->new( {root => $self->root->fs->revision_root($rev, $pool)} ),
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
    my ($class, $fs, $view, $revision) = @_;
    my $pool = SVN::Pool->new;
    my $txn = $fs->begin_txn($revision, $view->pool);

    my $self = $class->new({ txn => $txn, root => $txn->root($pool),
			     view => $view, pool => $pool });

    $self->_apply_view_to_txn($txn, $view, $revision);

    return $self;
}

sub _apply_view_to_txn {
    my ($self, $txn, $view, $revision) = @_;
    my $root = $txn->root($view->pool);
    my $origroot = $root->fs->revision_root($revision);

    my $pool = SVN::Pool->new_default;
    for (@{$view->view_map}) {
	$pool->clear;
	my ($path, $orig) = @$_;

	if (defined $orig) {
	    # XXX: mkpdir
	    Carp::cluck if ref($origroot) ne '_p_svn_fs_root_t';
	    SVN::Fs::copy( $origroot, $orig,
			   $root, $path)
		    if $origroot->check_path($orig);
	}
	else {
	    if ($path =~ m/\*$/) {
		my $parent = $path->parent;
		my $entries = $root->dir_entries($parent);
		for (keys %$entries) {
		    $root->delete($parent->subdir($_));
		}
	    }
	    else {
		$root->delete($path);
	    }
	}
    }
    return;
}

1;
