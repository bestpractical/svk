package SVK::Log::ChangedPath;
use base qw( Class::Accessor::Fast );

SVK::Log::ChangedPath->mk_ro_accessors(qw( path root entry ));

sub new {
    my ($class, $root, $path_name, $path_entry) = @_;

    return bless {
        root  => $root,
        path  => $path_name,
        entry => $path_entry,
    }, $class;
}

sub copied_from {
    my ($self) = @_;
    return $self->root()->copied_from( $self->path() );
}

sub is_copy {
    my ($self) = @_;
    my ($rev, $path) = $self->copied_from();
    return defined $path ? 1 : 0;
}

sub _calculate_actions {
    my ($self) = @_;

    my $entry = $self->entry();

    require SVK::Command::Log;
    my $action     = $SVK::Command::Log::chg->[ $entry->change_kind() ];
    my $propaction = ' ';
    if ( $action eq 'D' ) {
        return ($action, $propaction);
    }

    my $text_mod = $entry->text_mod();
    if ( $action eq 'M' ) {
        $propaction = 'M' if $entry->prop_mod();
        $action     = ' ' if !$text_mod;
    }
    elsif ($action eq 'A' && $self->is_copy() && $text_mod ) {
        $action = 'M';
    }

    return ($action, $propaction);
}

sub action {
    return ( $_[0]->_calculate_actions() )[0];
}
sub property_action {
    return ( $_[0]->_calculate_actions() )[1];
}

1;

__END__

=head1 NAME
 
SVK::Log::ChangedPath - changes made to a path during in a revision
 
=head1 SYNOPSIS
 
    print "Path of change : ", $changed_path->path(), "\n";
    print "Action         : ", $changed_path->action(), "\n";
    print "Property action: ", $changed_path->property_action(), "\n";
    ...

=head1 DESCRIPTION

An object of this class represents a path which was modified in a particular
revision.  It provides methods to determine how the path was modified.  This
class is intended for indirect use by log filters.  Log filters may want to
report about the paths that were modified during a particular revision, but
they shouldn't have to know the details of how SVK determines those changes.
Encapsulating that knowledge in this class allows log filters to focus on
formatting, displaying and analyzing the logs.
 
 
=head1 METHODS 
 
=head2 new $root, $path_name, $path_entry

SVK::Log::ChangedPath objects are usually created from SVK::Log::ChangedPaths
and it's probably meaningless to construct them anywhere else.  Nevertheless,
here's a brief description.

C<$root> should be the return value from C<< SVK::Path->root() >>
C<$path_name> is the key in the hash returned by C<< $root->paths_changed() >>
C<$path_entry> is the corresponding value from that hash.

=head2 action

Returns a single character indicating the way in which the content of the path
was changed.  This letter is the same as the first column in the path line
that you see when you do C<svk log --verbose>

=head2 copied_from

If the path was copied from somewhere else in this revision, C<copied_from()>
returns the revision and path from which this path was copied.  The values are
returned as a list with items in that order.  Namely,

 if ( $changed_path->is_copy() ) {
    my ($rev, $path) = $changed_path->copied_from();
    print "Copied from $path in revision $rev\n";
 }

=head2 is_copy

Returns true if the path was copied from somewhere else in this revision,
otherwise, returns false.

=head2 path

Returns the full depot path for this changed path.

=head2 property_action

Returns a single character indicating the way in which the properties of the path
were changed.  This letter is the same as the second column in the path line
that you see when you do C<svk log --verbose>
 
 
=head1 DIAGNOSTICS
 
None
 
=head1 CONFIGURATION AND ENVIRONMENT
 
SVK::Log::ChangedPath requires no configuration files or environment variables.
 
=head1 DEPENDENCIES
 
=over

=item *

SVK::Command::Log

=back
 
=head1 INCOMPATIBILITIES
 
None known.
 
=head1 BUGS AND LIMITATIONS
 
None known.
 
=head1 AUTHOR
 
Michael Hendricks  <michael@ndrix.org>
 
=head1 LICENSE AND COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.
 
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

