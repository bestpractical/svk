package SVK::Command::List;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('r|revision=i'  => 'rev',
     'v|verbose'	   => 'verbose',
     'R|recursive'   => 'recursive');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return @arg;
}

sub run {
    my ($self, @arg) = @_;
    for (@arg) {
	my (undef, $path, undef, undef, $repos) = main::find_repos_from_co_maybe ($_, 1);
	my $pool = SVN::Pool->new_default;
	my $fs = $repos->fs;
	my $root = $fs->revision_root ($self->{rev} || $fs->youngest_rev);
	unless ($root->check_path ($path) == $SVN::Node::dir) {
	    print "$path is not a versioned directory\n";
	    next;
	}
	my $entries = $root->dir_entries ($path);
	for (sort keys %$entries) {
	    print $_.($entries->{$_}->kind == $SVN::Node::dir ? '/' : '')."\n";
	}
    }
    return;
}

1;

=head1 NAME

list - List entries in a directory from depot.

=head1 SYNOPSIS

    list [DEPOTPATH|PATH...]

=head1 OPTIONS

    options:
    -r [--revision] REV:    revision
    -R [--recursive]:       recursive

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
