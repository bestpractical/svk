package SVK::Command::Mirror;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;
use SVK::Util qw( HAS_SVN_MIRROR is_uri );

sub options {
    ('l|list'  => 'list',
     'd|delete|detach'=> 'detach',
     'upgrade' => 'upgrade',
     'relocate'=> 'relocate');
}

sub parse_arg {
    my ($self, @arg) = @_;

    return (@arg ? @arg : undef) if $self->{list};
    @arg = ('//') if $self->{upgrade} and !@arg;
    return if !@arg;

    my $path = shift(@arg);

    # Allow "svk mi uri://... //depot" to mean "svk mi //depot uri://"
    if (is_uri($path)) {
        ($arg[0], $path) = ($path, $arg[0]);
    }

    return ($self->arg_depotpath ($path), @arg);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target, $source, @options) = @_;
    die loc("cannot load SVN::Mirror") unless HAS_SVN_MIRROR;

    if ($self->{upgrade}) {
	SVN::Mirror::upgrade ($target->{repos});
	return;
    }
    elsif ($self->{list}) {
        my $fmt = "%-20s\t%-s\n";
        printf $fmt, loc('Path'), loc('Source');
        print '=' x 60, "\n";
        my @depots = (defined($_[1])) ? @_[1..$#_] : sort keys %{$self->{xd}{depotmap}};
        foreach my $depot (@depots) {
            $depot =~ s{/}{}g;
            $target = $self->arg_depotpath ("/$depot/");

            my @paths = SVN::Mirror::list_mirror ($target->{repos});
            my $fs = $target->{repos}->fs;
            my $root = $fs->revision_root ($fs->youngest_rev);
            my $name = $target->depotname;
            foreach my $path (@paths) {
                my $m = SVN::Mirror->new(
                    target_path => $path,
                    repos => $target->{repos},
                    get_source => 1
                );
                printf $fmt, "/$name$path", $m->{source};
            }
        }
        return;
    }
    elsif ($self->{detach}) {
	my ($m, $mpath) = SVN::Mirror::is_mirrored ($target->{repos},
						    $target->{path});

        die loc("%1 is not a mirrored path.\n", $target->{depotpath}) if !$m;
        die loc("%1 is inside a mirrored path.\n", $target->{depotpath}) if $mpath;

	$m->delete(1); # remove svm:source and svm:uuid too
        print loc("Mirror path '%1' detached.\n", $target->{depotpath});
        return;
    }

    my $m = SVN::Mirror->new (target_path => $target->{path},
			      source => $source,
			      repospath => $target->{repospath},
			      repos => $target->{repos},
			      options => \@options,
			      config => $self->{svnconfig},
			      pool => SVN::Pool->new,
			      # XXX: remove in next svn::mirror release
			      target => $target->{repospath},
			     );

    if ($self->{relocate}) {
        $m->relocate;
        return;
    }

    $m->init or die loc("%1 already mirrored, use 'svk mirror --detach' to remove it first.\n", $target->{depotpath});

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Mirror - Initialize a mirrored depotpath

=head1 SYNOPSIS

 mirror [http|svn]://host/path DEPOTPATH
 mirror cvs::pserver:user@host:/cvsroot:module/... DEPOTPATH
 mirror p4:user@host:1666://path/... DEPOTPATH

 # You may also list the target part first:
 mirror DEPOTPATH [http|svn]://host/path

 mirror --list [DEPOT...]
 mirror --relocate DEPOTPATH [http|svn]://host/path 
 mirror --detach DEPOTPATH
 mirror --upgrade //
 mirror --upgrade /DEPOT/

=head1 OPTIONS

 -l [--list]            : list mirrored paths
 -d [--detach]          : mark a depotpath as no longer mirrored
 --relocate             : relocate the mirror to another URI
 --upgrade              : upgrade mirror state to the latest version

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
