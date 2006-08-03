package SVK::Root::Checkout;
use strict;
use SVK::Util qw(abs2rel md5_fh is_symlink);

use base qw{ Class::Accessor::Fast };

__PACKAGE__->mk_accessors(qw(path));

sub file_contents {
    my ($self, $path, $pool) = @_;
    my ($copath, $root) = $self->_get_copath($path, $pool);
    return SVK::XD::get_fh($root, '<', $path, $copath);
}

sub file_md5_checksum {
    my ($self, $path, $pool) = @_;
    my $fh = $self->file_contents($path, $pool);
    return md5_fh($fh);
}

sub check_path {
    my ($self, $path, $pool) = @_;
    my ($copath,$root) = $self->_get_copath($path, $pool);

    lstat ($copath);
    return $SVN::Node::none unless -e _;

    return (is_symlink || -f _) ? $SVN::Node::file : $SVN::Node::dir
	if $self->path->xd->{checkout}->get($copath)->{'.schedule'} or
	    $root->check_path($path, $pool);
    return $SVN::Node::unknown;
}

sub node_prop { 
    my ($self, $path, $propname, $pool) = @_;
    return $self->node_proplist($path, $pool)->{$propname};
}

sub node_proplist { 
    my ($self, $path, $pool) = @_;
    my ($copath,$root) = $self->_get_copath($path, $pool);
    return $self->path->xd->get_props($root, $path, $copath);
}

sub node_created_rev {
    my ($self, $path, $pool) = @_;
    my ($copath, $root) = $self->_get_copath($path, $pool);
    # ({ kind => $self->path->xd->{checkout}->get($copath)->{'.schedule'} ?
    # XXX: fails on really unknown?
    return $root->check_path($path, $pool) ? $root->node_created_rev($path, $pool) : undef;
}

# XXX: node_history / entry

sub closest_copy {
    my ($self, $path, $pool) = @_;
    my ($copath, $root) = $self->_get_copath($path, $pool);
    my $entry = $self->path->xd->{checkout}->get($copath);
    my $kind = $entry->{'.schedule'} || '';

    return $root->closest_copy($path, $pool) unless $kind eq 'add';

    return ($self, $entry->{scheduleanchor}) if $entry->{scheduleanchor} && $entry->{'.copyfrom'};
}

sub copied_from {
    my ($self, $path, $pool) = @_;
    my ($copath, $root) = $self->_get_copath($path, $pool);
    my $entry = $self->path->xd->{checkout}->get($copath);
    my $kind = $entry->{'.schedule'};

    return $root->copied_from($path, $pool) unless $kind eq 'add';
    my ($source_path, $source_rev) = SVK::XD::_copy_source($entry, $copath);
    return ($source_rev, $source_path);
}

sub dir_entries {
    my ($self, $path, $pool) = @_;
    my ($copath,$root) = $self->_get_copath($path, $pool);

    my $entries = $root->dir_entries($path, $pool);
    my $coentries;
    opendir my ($dir), $copath or die "$copath: $!";
    for (readdir($dir)) {
	next if m/^\.+$/;
	lstat $_;
	my $kind = -d _ ? $SVN::Node::dir : $SVN::Node::file;
	if ($entries->{$_}) {
	    $coentries->{$_} = $entries->{$_};
	}
	else {
	    # Do we know about the node?
	    $coentries->{$_} = SVK::Root::Checkout::Entry->new
		({ kind => $self->path->xd->{checkout}->get($copath)->{'.schedule'} ?
		   $kind : $SVN::Node::unknown });
	}
    }

    return $coentries;
}

sub fs {
    $_[0]->path->repos->fs;
}

sub AUTOLOAD {
    my ($self, $path) = @_;
    our $AUTOLOAD;
    my $func = $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]/;
    die "$self $AUTOLOAD $path";
}

sub _get_copath {
    my ($self, $path, $pool) = @_;
    # XXX: copath shouldn't be copath_anchor!
    my $copath = abs2rel($path, $self->path->path_anchor => $self->path->copath);
    my $root;
    ($root, $_[1]) = $self->path->source->root->get_revision_root
	($path, $self->path->xd->{checkout}->get($copath)->{revision}, $pool);
    return ($copath, $root);
}

package SVK::Root::Checkout::Entry;
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(kind));

sub AUTOLOAD {
    my ($self) = @_;
    our $AUTOLOAD;
    my $func = $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]/;
    die "$self $AUTOLOAD";
}

1;
