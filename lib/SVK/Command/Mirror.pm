package SVK::Command::Mirror;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;
use SVK::Util qw( HAS_SVN_MIRROR is_uri get_prompt );

sub options {
    ('l|list'  => 'list',
     'd|delete|detach'=> 'detach',
     'upgrade' => 'upgrade',
     'relocate'=> 'relocate',
     'recover'=> 'recover');
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

    $source = ("file://$target->{repospath}") if $self->{recover};

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
    elsif ($self->{recover}) {
        $self->recover_headrev ($target, $m);
        $self->recover_list_entry ($target, $m);
        return;
    }

    $m->init or die loc("%1 already mirrored, use 'svk mirror --detach' to remove it first.\n", $target->{depotpath});

    return;
}

sub recover_headrev {
    my ($self, $target, $m) = @_;

    my $fs = $m->{fs};
    my $pool = SVN::Pool->new_default ($m->{pool});
    my $hist = $fs->revision_root ($fs->youngest_rev)->
        node_history ($m->{target_path});

    my ($props, $headrev, $rev, $firstrev, $skipped, $uuid, $rrev);
    while ($hist = $hist->prev (1)) {
        $rev = ($hist->location)[1];
        $firstrev ||= $rev;
        print loc("Analyzing revision %1...\n", $rev),
              ('-' x 70),"\n",
              $fs->revision_prop ($rev, 'svn:log'), "\n";
        if ( $headrev = $fs->revision_prop ($rev, 'svm:headrev') ) {
            ($uuid, $rrev) = split(/[:\n]/, $headrev);
            $props = $fs->revision_proplist($rev);
            get_prompt(loc(
                "Found merge ticket at revision %1 (remote %2); use it? [y] ",
                $rev, $rrev
            )) =~ /^[Nn]/ or last;
            undef $headrev;
        }
        $skipped++;
    }

    if (!$headrev) {
        die loc("No mirror history found; cannot recover.\n");
    }

    if (!$skipped) {
        print loc("No need to revert; it is already the head revision.\n");
        return;
    }

    get_prompt(loc("Revert to revision %1 and discard %*(%2,revision)? [n] ", $rev, $skipped))
        =~ /^[Yy]/ or die loc("Aborted.\n");

    my $rm_edit = $self->get_commit_editor(
        $fs->revision_root ($fs->youngest_rev),
        sub { print loc("Committed revision %1.\n", $_[0]) }, '/', %$target
    );
    $rm_edit->open_root;
    $rm_edit->delete_entry ($m->{target_path});
    $rm_edit->close_edit;

    my $cp_edit = $self->get_commit_editor(
        $fs->revision_root ($fs->youngest_rev),
        sub {
            print loc("Committed revision %1.\n", $_[0]);
            $fs->change_rev_prop ($_[0], $_ => $props->{$_})
                foreach sort keys %$props;
        }, '/', %$target
    );
    $cp_edit->open_root;
    $cp_edit->copy_directory (
        $m->{target_path},
        "file://$m->{target}$m->{target_path}",
        $rev,
    );
    $cp_edit->close_edit;

    print loc("Mirror state successfully recovered.\n");
    return;
}

sub recover_list_entry {
    my ($self, $target, $m) = @_;

    my %mirrors = map { ($_ => 1) } SVN::Mirror::list_mirror ($target->{repos});

    return if $mirrors{$m->{target_path}}++;

    my $fs = $m->{fs};
    my $pool = SVN::Pool->new_default ($m->{pool});
    my $ps_edit = $self->get_commit_editor(
        $fs->revision_root ($fs->youngest_rev),
        sub { print loc("Committed revision %1.\n", $_[0]) }, '/', %$target
    );
    $ps_edit->open_root;
    $ps_edit->change_dir_prop ('/', 'svm:mirror', join("\n", (grep length, sort keys %mirrors), ''));
    $ps_edit->close_edit;

    print loc("%1 added back to the list of mirrored paths.\n", $target->{report}); 
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
 mirror --recover DEPOTPATH

 mirror --upgrade //
 mirror --upgrade /DEPOTNAME/

=head1 OPTIONS

 -l [--list]            : list mirrored paths
 -d [--detach]          : mark a depotpath as no longer mirrored
 --relocate             : relocate the mirror to another URI
 --recover              : recover the state of a mirror path
 --upgrade              : upgrade mirror state to the latest version

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
