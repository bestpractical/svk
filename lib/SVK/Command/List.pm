package SVK::Command::List;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 0;
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( to_native get_encoder );
use Date::Parse qw(str2time);
use Date::Format qw(time2str);

sub options {
    ('r|revision=i'  => 'rev',
     'v|verbose'	   => 'verbose',
     'f|full-path'      => 'fullpath',
     'd|depth=i'      => 'depth');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_co_maybe ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;
    _do_list($self, 0, $_) for @arg;
    return;
}

sub _do_list {
    my ($self, $level, $target) = @_;
    my $pool = SVN::Pool->new_default;
    $target->as_depotpath ($self->{rev});
    my $root = $target->root;
    unless ((my $kind = $root->check_path ($target->{path})) == $SVN::Node::dir) {
       print loc("Path %1 is not a versioned directory\n", $target->{path})
           unless $kind == $SVN::Node::file;
       return;
    }

    # XXX: SVK::Target should take care of this.
    $target->{depotpath} =~ s|/$||;
    my $entries = $root->dir_entries ($target->{path});
    my $enc = get_encoder;
    for (sort keys %$entries) {
	my $isdir = ($entries->{$_}->kind == $SVN::Node::dir);

        if ($self->{verbose}) {
	    my $rev = $root->node_created_rev ("$target->{path}/$_");
            my $fs = $target->{'repos'}->fs;

            my $svn_date =
                $fs->revision_prop ($rev, 'svn:date');

	    # The author name may be undef
            no warnings 'uninitialized';

	    # Additional fields for verbose: revision author size datetime
            printf "%7ld %-8.8s %10s %12s ", $rev,
                $fs->revision_prop ($rev, 'svn:author'),
                ($isdir) ? "" : $root->file_length ("$target->{path}/$_"),
		time2str ("%b %d %H:%M", str2time ($svn_date));
        }

        if ($self->{'fullpath'}) {
	    my $dpath = $target->{depotpath};
	    to_native ($dpath, 'path', $enc);
            print $dpath.'/';
        } else {
            print " " x ($level);
        }
	my $path = $_;
	to_native ($path, 'path', $enc);
        print $path.($isdir ? '/' : '')."\n";

	if ($isdir && ($self->{recursive}) &&
	    (!$self->{'depth'} ||( $level < $self->{'depth'} ))) {
	    _do_list($self, $level+1, $target->new (path => "$target->{path}/$_",
						    depotpath => "$target->{depotpath}/$_"));
	}
    }
}

1;

__DATA__

=head1 NAME

SVK::Command::List - List entries in a directory from depot

=head1 SYNOPSIS

 list [DEPOTPATH | PATH...]

=head1 OPTIONS

 -r [--revision] arg    : act on revision ARG instead of the head revision
 -R [--recursive]       : descend recursively
 -d [--depth] arg       : recurse at most ARG levels deep; use with -R
 -f [--full-path]       : show pathname for each entry, instead of a tree
 -v [--verbose]         : print extra information

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
