package SVK::Command::List;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;

sub options {
    ('r|revision=i'  => 'rev',
     'v|verbose'	   => 'verbose',
     'f|full-path'      => 'fullpath',
     'd|depth=i'      => 'depth',
     'R|recursive'   => 'recursive');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_co_maybe ($_)} @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;
    _do_list($self, 0, $_) for @arg;
    return;
}

sub _do_list {
    my ($self, $level, $target) = @_;
    my $pool = SVN::Pool->new_default;
    $target->depotpath ($self->{rev});
    my $root = $target->root;
    unless ((my $kind = $root->check_path ($target->{path})) == $SVN::Node::dir) {
       print loc("Path %1 is not a versioned directory\n", $target->{path})
           unless $kind == $SVN::Node::file;
       return;
    }

    # XXX: SVK::Target should take care of this.
    $target->{depotpath} =~ s|/$||;
    my $entries = $root->dir_entries ($target->{path});
    for (sort keys %$entries) {
	my $isdir = ($entries->{$_}->kind == $SVN::Node::dir);
        if ($self->{'fullpath'}) {
	    print $target->{depotpath}.'/';
        }
        else {
	    print " " x ($level);
        }
	print $_.($isdir ? '/' : '')."\n";
	if ($isdir && ($self->{recursive}) &&
	    (!$self->{'depth'} ||( $level < $self->{'depth'} ))) {
	    _do_list($self, $level+1,
		     SVK::Target->new (%$target,
				       path => "$target->{path}/$_",
				       depotpath => "$target->{depotpath}/$_"));
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

 -r [--revision] REV:    revision
 -R [--recursive]:       recursive
 -v [--verbose]:         Needs description
 -d [--depth] LEVEL:     Recurse LEVEL levels.  Only useful with -R
 -f [--full-path]:       Show the full path of each entry, rather than
                         an indented hierarchy

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
