package SVK::Log::Filter::Author;

use strict;
use warnings;
use base qw( SVK::Log::Filter::Selection );

use SVK::I18N;
use List::MoreUtils qw( any );

sub setup {
    my ($self) = @_;

    my $search = $self->{argument}
        or die loc("Author: at least one author name is required.\n");

    my @matching_authors = split /\s* , \s*/xms, $search;
    $self->{names} = \@matching_authors;
    $self->{wants_none} = grep { $_ eq '(none)' } @matching_authors;
}

sub revision {
    my ($self, $args) = @_;
    my $props = $args->{props};

    # look for a matching, non-existent author
    my $author = $props->{'svn:author'};
    if ( !defined $author ) {
        return if $self->{wants_none};
        $self->pipeline('next');
    }

    # look for a matching, existent author
    return if any { $_ eq $author } @{ $self->{names} };

    # no match, so skip to the next revision
    $self->pipeline('next');
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

Author leaves all properties and the stash intact.

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
