package SVK::Command::List;
use strict;
our $VERSION = '0.13';

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;

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

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;
    _do_list($self, 0, @arg);
    return;
}

sub _do_list {
    my ($self, $level, @arg) = @_;
    for (@arg) {
	my (undef, $path, $copath, undef, $repos) = $self->{xd}->find_repos_from_co_maybe ($_, 1);
	my $pool = SVN::Pool->new_default;
	my $fs = $repos->fs;
	my $root = $fs->revision_root ($self->{rev} || $fs->youngest_rev);
	unless ($root->check_path ($path) == $SVN::Node::dir) {
	    print loc("Path %1 is not a versioned directory\n", $path) unless ($root->check_path($path) == $SVN::Node::file);
	    next;
	}
	my $entries = $root->dir_entries ($path);
	for (sort keys %$entries) {
	    print "\t" x ($level);
	    print $_.($entries->{$_}->kind == $SVN::Node::dir ? '/' : '')."\n";
	    if (($self->{recursive}) && 
	    	($entries->{$_}->kind == $SVN::Node::dir)) {
                if (defined $copath) {
		    _do_list($self, $level+1, "$copath/$_");
                }
                else {
                    _do_list($self, $level+1, "/$path/$_");
                }
	    }
	}
    }
}

1;

__DATA__

=head1 NAME

SVK::Command::List - List entries in a directory from depot

=head1 SYNOPSIS

    list [DEPOTPATH|PATH...]

=head1 OPTIONS

    options:
    -r [--revision] REV:    revision
    -R [--recursive]:       recursive
    -v [--verbose]:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
