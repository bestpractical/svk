package SVK::Inspector::XD;

use strict;
use warnings;

use base qw {
	SVK::Inspector
};

require SVN::Core;
require SVN::Repos;
require SVN::Fs;

use SVK::Util qw( is_symlink md5_fh );

=head1 NAME

SVK::Inspector::XD - checkout inspector

=head1 SYNOPSIS

 use SVK::XD;
 use SVK::Inspector::XD;

 my $xd = SVK::XD->new(...);
 my $inspector = SVK::Inspector::XD->new({xd => $xd, path => $target});

=cut

__PACKAGE__->mk_accessors(qw(xd path xdroot));

sub exist { 
    my ($self, $path, $pool) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);

    lstat ($copath);
    return $SVN::Node::none unless -e _;

    return (is_symlink || -f _) ? $SVN::Node::file : $SVN::Node::dir
	if $self->xd->{checkout}->get ($copath)->{'.schedule'} or
	    $self->xdroot->check_path ($path, $pool);
    return $SVN::Node::unknown;
}

sub localmod { 
    my ($self, $path, $checksum) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);

    # XXX: really want something that returns the file.
    my $base = SVK::XD::get_fh($self->xdroot, '<', $path, $copath);
    my $md5 = md5_fh ($base);
    return undef if $md5 eq $checksum;
    seek $base, 0, 0;
    return [$base, undef, $md5];
}

sub localprop { 
    my ($self, $path, $propname) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);

    return $self->xd->get_props ($self->xdroot, $path, $copath)->{$propname};
}

sub dirdelta { 
    my ($self, $path, $base_root, $base_path, $pool) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);
    my $modified = {};
    $self->xd->checkout_delta(
         # XXX: proper anchor handling
         path => $path,
	 target => defined $self->path->path_target,
         copath => $copath,
         base_root => $base_root,
         base_path => $base_path,
         xdroot => $self->xdroot,
         nodelay => 1,
         depth => 1,
         editor => $self->dirdelta_status_editor($modified),
         absent_as_delete => 1,
         cb_unknown => \&SVK::Editor::Status::unknown,
    );
    return $modified;
}

sub get_paths {
    my ($self, $path) = @_;
    $path = $self->translate($path);
    my $copath = $self->path->copath($path);
    $path = length $path ? $self->path->path_anchor."/$path" : $self->path->path_anchor;

    return ($path, $copath);
}

1;
