package SVK::Log::Filter::Grep;

use strict;
use warnings;
use SVK::I18N;
use SVK::Log::Filter;

sub setup {
    my ($stash) = $_[STASH];

    my $search = $stash->{argument};
    my $rx = eval "qr{$search}i"
        or die loc( "Grep: Invalid regular expression '%1'.\n", $search );

    $stash->{grep_pattern} = $rx;
}

sub revision {
    my ($stash, $props) = @_[STASH, PROPS];

    my $rx  = $stash->{grep_pattern};
    my $log = $props->{'svn:log'};
    pipeline('next') if  $log !~ /$rx/;
}

1;

__END__

=head1 SYNOPSIS

SVK::Log::Filter::Grep - search log messages for a given pattern

=head1 DESCRIPTION

The Grep filter requires a single Perl pattern (regular expression) as its
argument.  The pattern is then applied to the svn:log property of each
revision it receives.  If the pattern matches, the revision is allowed to
continue down the pipeline.  If the pattern fails to match, the pipeline
immediately skips to the next revision.

The pattern is applied with the /i modifier (case insensitivity).  If you want
case-sensitivity or other modifications to the behavior of your pattern, you
must use the "(?imsx-imsx)" extended pattern (see "perldoc perlre" for
details).  For example, to search for log messages that match exactly the
characters "foo" you might use

    svk log --filter "grep (?-i)foo"

However, to search for "foo" without regards for case, one might try

    svk log --filter "grep foo"

The result of any capturing parentheses inside the pattern are B<not>
available.  If demand dictates, the Grep filter could be modified to place the
captured value somewhere in the stash for other filters to access.

If the pattern contains a pipe character ('|'), it must be escaped by
preceding it with a '\' character.  Otherwise, the portion of the pattern
after the pipe character is interpreted as the name of a log filter.

=head1 STASH/PROPERTY MODIFICATIONS

Grep leaves all properties intact and only modifies the stash under the "grep_"
namespace.

=head1 AUTHORS

Michael Hendricks E<lt>michael@palmcluster.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
