package SVK::Log::Filter::Author;

use strict;
use warnings;
use SVK::I18N;
use SVK::Log::Filter;

sub setup {
    my ($stash) = $_[STASH];

    my $search = $stash->{argument}
        or die loc("Author: at least one author name is required.\n");

    my @matching_authors        = split /\s* , \s*/xms, $search;
    $stash->{author_names}      = \@matching_authors;
    $stash->{author_wants_none} = grep { $_ eq '(none)' } @matching_authors;
}

sub revision {
    my ( $stash, $props ) = @_[ STASH, PROPS ];

    # look for a matching, non-existent author
    my $author = $props->{'svn:author'};
    if ( !defined $author ) {
        return if $stash->{author_wants_none};
        pipeline('next');
    }

    # look for a matching, existent author
    for my $needle ( @{ $stash->{author_names} } ) {
        return if $author eq $needle;
    }

    pipeline('next');    # no match so skip
}

1;

__END__

=head1 SYNOPSIS

SVK::Log::Filter::Author - search revisions for given authors

=head1 DESCRIPTION

The Author filter accepts a comma-separated list of author names.  If the
svn:author property is equal to any of the names, the revision is allowed to
continue down the pipeline.  Otherwise, the revision is skipped.  The special
author name "(none)" means to look for revisions with no svn:author property.

For example, to search for all commits by either "jack" or "jill" one might do

    svk log --filter "author jill,jack"

To locate those revisions without an author, this command may be used

    svk log --filter "author (none)"

Of course "(none)" may be used in a list with other authors

    svk log --filter "author jill,(none)"

=head1 STASH/PROPERTY MODIFICATIONS

Author leaves all properties intact and only modifies the stash under the
"author_" namespace.

=head1 AUTHORS

Michael Hendricks E<lt>michael@palmcluster.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
