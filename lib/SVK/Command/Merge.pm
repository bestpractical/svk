package SVK::Command::Merge;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Delay;
use SVK::Command::Log;
use SVK::Merge;
use SVK::Util qw( get_buffer_from_editor find_svm_source resolve_svm_source traverse_history );

sub options {
    ($_[0]->SUPER::options,
     'a|auto'		=> 'auto',
     'l|log'		=> 'log',
     'summary'		=> 'summary',
     'remoterev'	=> 'remoterev',
     'track-rename'	=> 'track_rename',
     'host=s'   	=> 'host',
     'I|incremental'	=> 'incremental',
     'verbatim'		=> 'verbatim',
     'no-ticket'	=> 'no_ticket',
     'r|revision=s'	=> 'revspec',
     'c|change=s',	=> 'chgspec',
     't|to'             => 'to',
     'f|from'           => 'from',
     's|sync'           => 'sync');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg > 1;

    if (!$self->{to} && !$self->{from}) {
        return if scalar (@arg) == 0;
	my ($src, $dst) = ($self->arg_depotpath ($arg[0]), $self->arg_co_maybe ($arg[1] || ''));
	die loc("Can't merge across depots.\n") unless $src->same_repos ($dst);
        return ($src, $dst);
    }

    if (scalar (@arg) == 2) {
        die loc("Cannot specify 'to' or 'from' when specifying a source and destination.\n");
    }

    if ($self->{to} && $self->{from}) {
        die loc("Cannot specify both 'to' and 'from'.\n");
    }

    my $target1 = $self->arg_co_maybe (@arg ? $arg[0] : '');
    my $target2;

    if ($self->{from}) {
        # When using "from", $target1 must always be a depotpath.
        if (defined $target1->{copath}) {
            # Because merging under the copy anchor is unsafe, we always merge
            # to the most immediate copy anchor under copath root.
            ($target1, $target2) = $self->find_checkout_anchor (
                $target1, 1, $self->{sync}
            );
            delete $target1->{copath};
        }
    }

    $target2 ||= $target1->copied_from($self->{sync});
    if (!defined ($target2)) {
        die loc ("Cannot find the path which '%1' copied from.\n", $arg[0] || '');
    }

    return ( ($self->{from}) ? ($target1, $target2) : ($target2, $target1) );
}

sub lock {
    my $self = shift;
    $self->lock_target ($_[1]);
}

sub get_commit_message {
    my ($self, $log) = @_;
    return if $self->{check_only} || $self->{incremental};
    if (defined $self->{message}) {
	$self->{message} = join ("\n", grep {length $_} ($self->{message}, $log));
	$self->decode_commit_message;
    }
    else {
	$self->SUPER::get_commit_message ($log);
    }
}

sub run {
    my ($self, $src, $dst) = @_;
    my $merge;
    my $repos = $src->{repos};
    my $fs = $repos->fs;
    my $yrev = $fs->youngest_rev;

    if (my @mirrors = $dst->contains_mirror) {
	die loc ("%1 can not be used as merge target, because it contains mirrored path: ", $dst->{report})
	    .join(",", @mirrors)."\n"
		unless $mirrors[0] eq $dst->path;
    }

    if ($self->{sync}) {
        my $sync = $self->command ('sync');
	my (undef, $m) = resolve_svm_source($repos, find_svm_source($repos, $src->{path}));
        if ($m->{target_path}) {
            $sync->run($self->arg_depotpath('/' . $src->depotname .  $m->{target_path}));
            $src->refresh_revision;
        }
    }

    if ($dst->root ($self->{xd})->check_path ($dst->path) != $SVN::Node::dir) {
	$src->anchorify; $dst->anchorify;
    }

    # for svk::merge constructor
    $self->{dst} = $dst;
    $self->{report} = defined $dst->{copath} ? $dst->{report} : undef;
    if ($self->{auto}) {
	die loc("No need to track rename for smerge\n")
	    if $self->{track_rename};
	++$self->{no_ticket} if $self->{patch};
	# avoid generating merge ticket pointing to other changes
	$src->normalize; $dst->normalize;
	$merge = SVK::Merge->auto (%$self, repos => $repos, target => '',
				   ticket => !$self->{no_ticket},
				   src => $src);
	print $merge->info;
	print $merge->log(1) if $self->{summary};
    }
    else {
	die loc("Incremental merge not supported\n") if $self->{incremental};
	my @revlist = $self->parse_revlist;
	die "multi-merge not yet" if $#revlist > 0;
	my ($baserev, $torev) = @{$revlist[0]};
	$merge = SVK::Merge->new
	    (%$self, repos => $repos, src => $src->new (revision => $torev),
	     base => $src->new (revision => $baserev), target => '',
	     fromrev => $baserev);
    }

    if ($merge->{fromrev} == $merge->{src}{revision}) {
	print loc ("Empty merge.\n");
	return;
    }

    $self->get_commit_message ($self->{log} ? $merge->log(1) : '')
	unless $dst->{copath};

    if ($self->{incremental} && !$self->{check_only}) {
	die loc ("Not possible to do incremental merge without a merge ticket.\n")
	    if $self->{no_ticket};
	print loc ("-m ignored in incremental merge\n") if $self->{message};
	my @rev;

        traverse_history (
            root        => $src->root,
            path        => $src->{path},
            cross       => 0,
            callback    => sub {
                my $rev = $_[1];
                return 0 if $rev <= $merge->{fromrev}; # last
                unshift @rev, $rev;
                return 1;
            },
        );

	my $spool = SVN::Pool->new_default;
	my $previous_base;
	foreach my $rev (@rev) {
	    $merge = SVK::Merge->auto (%$merge, src => $src->new (revision => $rev));
	    if ($previous_base) {
		$merge->{fromrev} = $previous_base;
	    }

	    print '===> '.$merge->info;
	    $self->{message} = $merge->log (1);

	    last if $merge->run ($self->get_editor ($dst));
	    # refresh dst
	    $dst->{revision} = $fs->youngest_rev;
	    $previous_base = $rev;
	    $spool->clear;
	}
    }
    else {
	print loc("Incremental merge not guaranteed even if check is successful\n")
	    if $self->{incremental};
	$merge->run ($self->get_editor ($dst, undef, $self->{auto} ? $src : undef));
	delete $self->{save_message};
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Merge - Apply differences between two sources

=head1 SYNOPSIS

 merge -r N:M DEPOTPATH [PATH]
 merge -r N:M DEPOTPATH1 DEPOTPATH2
 merge -r N:M [--to|--from] [PATH]

=head1 OPTIONS

 -r [--revision] N:M    : act on revisions between N and M
 -c [--change] N        : act on change N (between revisions N-1 and N)
 -C [--check-only]      : try operation but make no changes
 -I [--incremental]     : apply each change individually
 -a [--auto]            : merge from the previous merge point
 -l [--log]             : use logs of merged revisions as commit message
 -s [--sync]            : synchronize mirrored sources before update
 -t [--to]              : merge to the specified path
 -f [--from]            : merge from the specified path
 -P [--patch] NAME	: instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 --verbatim             : verbatim merge log without indents and header
 --no-ticket            : do not record this merge point
 --track-rename         : track changes made to renamed node

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
