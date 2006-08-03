package SVK::Log::ChangedPaths;

# a "constant" (inlined by the compiler)
sub ROOT () {0}

sub new {
    my ( $class, $root ) = @_;
    return bless [$root], $class;
}

sub paths {
    my ($self) = @_;

    my $root    = $self->[ROOT];
    my $changed = $root->paths_changed();

    my @changed;
    require SVK::Log::ChangedPath;
    for my $path_name ( sort keys %$changed ) {
        my $changed_path = SVK::Log::ChangedPath->new(
            $root,
            $path_name,
            $changed->{$path_name}
        );
        push @changed, $changed_path;
    }

    return @changed;
}

1;

__END__

=head1 NAME
 
SVK::Log::ChangedPaths - partly lazy list of SVK::Log::ChangedPath objects
 
=head1 SYNOPSIS
 
    use SVK::Log::ChangedPaths;
    my $changed_paths = SVK::Log::ChangedPaths->new( $root );
    for my $changed_path ( $changed_paths->paths() ) {
        ...
    }
  
=head1 DESCRIPTION

An object of this class represents a collection of details about the
files/directories that were changed in a particular revision.  Some log
filters want access to information about which paths were affected during a
certain revision and others don't.  Using this object allows the calculation
of path details to be postponed until it's truly needed.
 
 
=head1 METHODS 
 
=head2 new

Accepts the return value of C<< SVK::Path->root() >> as a parameter and constructs a
SVK::Log::ChangedPaths object from it.

=head2 paths

Returns a list of L<SVK::Log::ChangedPath> objects each of which represents
the details of the changes to a particular path.
 
 
=head1 DIAGNOSTICS
 
None
 
=head1 CONFIGURATION AND ENVIRONMENT
 
SVK::Log::ChangedPaths requires no configuration files or environment variables.
 
=head1 DEPENDENCIES
 
=over

=item *

SVK::Log::ChangedPath

=back
 
=head1 INCOMPATIBILITIES
 
None known
 
=head1 BUGS AND LIMITATIONS
 
None known
 
=head1 AUTHOR
 
Michael Hendricks  <michael@ndrix.org>
 
=head1 LICENSE AND COPYRIGHT
 
Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.
 
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

