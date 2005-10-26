package SVK::Inspector::Root;

use strict;
use warnings;

=over

=item cb_exist

Check if the given path exists.

=item cb_rev

Check the revision of the given path.

=item cb_localmod

Called when the merger needs to retrieve the local modification of a
file. Return an arrayref of filename, filehandle, and md5. Return
undef if there is no local modification.

=item cb_localprop

Called when the merger needs to retrieve the local modification of a
property. Return the property value.

=item cb_prop_merged

Called when properties are merged without changes, that is, the C<g>
status.

=item cb_dirdelta

When C<delete_entry> needs to check if everything to be deleted does
not cause conflict on the directory, it calls the callback with path,
base_root, and base_path. The returned value should be a hash with
changed paths being the keys and change types being the values.

=back

=cut

use base qw {
	Class::Accessor
	SVK::Inspector
};

sub new {
    my ($class, $root, $anchor, $base_rev) = @_;
    $class->SUPER::new( { root => $root, anchor => $anchor, base_rev => $base_rev });
}

__PACKAGE__->mk_accessors(qw{root anchor base_rev});

sub compat_cb {
    my $self = shift;
    return map { my $name = $_;  "cb_$name" => sub { $self->$name(@_) } }
           qw(exist rev localmod localprop dirdelta);
}

sub exist {
    my ($self, $path, $pool) = @_;
#    warn "==> exist";
    $path = $self->_anchor_path($path);
    return $self->root->check_path ($path, $pool);
}	       

sub rev { shift->base_rev; }

sub localmod {
    my ($self, $path, $checksum, $pool) = @_;
    $path = $self->_anchor_path($path);
    my $md5 = $self->root->file_md5_checksum ($path, $pool);
    return if $md5 eq $checksum;
    return [$self->root->file_contents ($path, $pool),
        undef, $md5];
}

sub localprop {
    my ($self, $path, $propname, $pool) = @_;
    $path = $self->_anchor_path($path);
    local $@;
    return eval { $self->root->node_prop ($path, $propname, $pool) };
}
	       
sub dirdelta { 
    my ($self, $path, $base_root, $base_path, $pool) = @_;
    my $modified;
    my $editor =  SVK::Editor::Status->new
       ( notify => SVK::Notify->new
                                 ( cb_flush => sub {
                                       my ($path, $status) = @_;
                                       $modified->{$path} = $status->[0];
                                   }));
    SVK::XD->depot_delta (oldroot => $base_root, newroot => $self->root,
             oldpath => [$base_path, ''],
             newpath => $self->_anchor_path($path),
             editor => $editor,
             no_textdelta => 1, no_recurse => 1);
    return $modified;
}

sub _anchor_path {
    my ($self, $path) = @_;
    my $anchor = $self->anchor;
    return $path if $path =~ m{^/};
    return $self->anchor."/$path";
}

1;
