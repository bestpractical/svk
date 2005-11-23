package SVK::Inspector;

use strict;
use warnings;

use base qw{ Class::Accessor::Fast };

__PACKAGE__->mk_accessors(qw(path_translations));

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    $self->path_translations([]) unless $self->path_translations; 

    return $self;
}

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


sub push_translation {
    my $self = shift;
    my $transform = shift;
    unless (ref $transform eq 'CODE') {
        die "Path transformations must be code refs";
    }
   
    push @{$self->path_translations}, $transform;
}

sub translate {
    my $self = shift;
    my $path = shift;
    
    return $path unless @{$self->path_translations};

    my $ret = "";
    for (@{$self->path_translations}) {
        $_->($path);
    }    
    
    return $path;
}

sub dirdelta_status_editor {
    my ($self, $modified) = @_;
    return SVK::Editor::Status->new
	( notify => SVK::Notify->new
	  ( cb_flush => sub {
		my ($path, $status) = @_;
		$modified->{$path} = $status->[0];
	    }));
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
