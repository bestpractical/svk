package SVK::Inspector::Root;

use strict;
use warnings;


use base qw {
	SVK::Inspector
};

__PACKAGE__->mk_accessors(qw{root anchor});


sub exist {
    my ($self, $path, $pool) = @_;
    $path = $self->_anchor_path($path);
    return $self->root->check_path ($path, $pool);
}

sub localmod {
    my ($self, $path, $checksum, $pool) = @_;
    $path = $self->_anchor_path($path);
    my $md5 = $self->root->file_md5_checksum ($path, $pool);
    return if $md5 eq $checksum;
    return [$self->root->file_contents ($path, $pool), undef, $md5];
}

sub localprop {
    my ($self, $path, $propname, $pool) = @_;
    $path = $self->_anchor_path($path);
    local $@;
    return eval { $self->root->node_prop ($path, $propname, $pool) };
}
sub dirdelta {
    my ($self, $path, $base_root, $base_path, $pool) = @_;
    $path = $self->_anchor_path($path);
    my $modified = {};
    my $entries = $self->root->dir_entries($path, $pool);
    my $base_entries = $base_root->dir_entries($base_path, $pool);
    my $spool = SVN::Pool->new_default;
    for (sort keys %$base_entries) {
	$spool->clear;
	my $entry = delete $entries->{$_};
	next if $base_root->check_path("$base_path/$_") == $SVN::Node::dir;
	if ($entry) {
	    $modified->{$_} = 'M'
		if $self->root->file_md5_checksum("$path/$_") ne
		    $base_root->file_md5_checksum("$base_path/$_");
	    next;
	}

	$modified->{$_} = 'D';
    }
    for (keys %$entries) {
	if ($entries->{$_}->kind == $SVN::Node::file) {
	    $modified->{$_} = 'A';
	}
	elsif ($entries->{$_}->kind == $SVN::Node::unknown) {
	    $modified->{$_} = '?';
	}
    }
    return $modified;
}

sub _anchor_path {
    my ($self, $path) = @_;
    $path = $self->translate($path);
    return $path if $path =~ m{^/};
    return $self->anchor unless length $path;
    return $self->anchor eq '/' ? "/$path" : $self->anchor."/$path";
}

1;
