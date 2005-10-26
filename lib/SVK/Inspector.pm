package SVK::Inspector;

use strict;
use warnings;

use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw(path_transforms));

=head1 NAME

SVK::Inspector - path inspector

=head1 DESCRIPTION

This class provides an interface through which the state of a C<SVK::Path> can
be inspected.

=head1 METHODS

=over

=item exist

Check if the given path exists.

=item rev

Check the revision of the given path.

=item localmod

Called when the merger needs to retrieve the local modification of a
file. Return an arrayref of filename, filehandle, and md5. Return
undef if there is no local modification.

=item localprop

Called when the merger needs to retrieve the local modification of a
property. Return the property value.

=item prop_merged

Called when properties are merged without changes, that is, the C<g>
status.

=item dirdelta

When C<delete_entry> needs to check if everything to be deleted does
not cause conflict on the directory, it calls the callback with path,
base_root, and base_path. The returned value should be a hash with
changed paths being the keys and change types being the values.

=back

=cut


sub compat_cb {
    my $self = shift;
    return map { my $name = $_;  "cb_$name" => sub { $self->$name(@_) } }
           qw(exist rev localmod localprop dirdelta);
}


sub push_path_transform {
    my $self = shift;
    my $transform = shift;
    unless (ref $transform eq 'CODE') {
        die "Path transformations must be code refs";
    }
    unshift @{$self->path_transforms}, $transform;
}

sub path_transform {
    my $self = shift;
    my $path = shift;
    
    return $path unless $self->path_transforms;
    
    for (@$self->path_tranasforms) {
        $path = $_->($path);
    }
    
    return $path;
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>
Norman Nunley E<lt>nnunley@gmail.comE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut


1;
