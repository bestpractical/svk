package SVK::Command::Merge;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Delay;
use SVK::Command::Log;
use SVK::Merge;
use SVK::Util qw( get_buffer_from_editor find_svm_source resolve_svm_source );

sub options {
    ($_[0]->SUPER::options,
     'a|auto'		=> 'auto',
     'l|log'		=> 'log',
     'remoterev'	=> 'remoterev',
     'track-rename'	=> 'track_rename',
     'host=s'   	=> 'host',
     'I|incremental'	=> 'incremental',
     'no-ticket'	=> 'no_ticket',
     'r|revision=s'	=> 'revspec',
     't|to'             => 'to',
     'f|from'           => 'from',
     's|sync'           => 'sync');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg > 1;

    if (!$self->{to} && !$self->{from}) {

        if (scalar (@arg) == 0) {
            return;
        }

        return ($self->arg_depotpath ($arg[0]), $self->arg_co_maybe ($arg[1] || ''));
    }

    if (scalar (@arg) == 2) {
        die loc("Cannot specify 'to' or 'from' when specifying a source and destination.\n");
    }

    if ($self->{to} && $self->{from}) {
        die loc("Cannot specify both 'to' and 'from'.\n");
    }

    my $target1 = $self->arg_co_maybe (@arg ? $arg[0] : '');

    if ($self->{from}) {
        # When using "from", $target1 must always be a depotpath.
        if (defined $target1->{copath}) {
            # Because merging under the copath anchor is unsafe,
            # cast it into a coroot now. -- XXX -- also see Update.pm
            my $entry = $self->{xd}{checkout}->get ($target1->{copath});
            $target1 = $self->arg_depotpath ($entry->{depotpath});
        }
    }

    my $target2 = $target1->copied_from($self->{sync});
    if (!defined ($target2)) {
        die loc ("Cannot find the path which '%1' copied from.\n", $arg[0]);
    }

    return ( ($self->{from}) ? ($target1, $target2) : ($target2, $target1) );
}

sub lock {
    my $self = shift;
    $_[1]->{copath} ? $self->lock_target ($_[1]) : $self->lock_none;
}

sub get_commit_message {
    my ($self, $log) = @_;
    return if $self->{check_only} || $self->{incremental};
    $self->{message} = defined $self->{message} ?
	join ("\n", $self->{message}, $log, '')
	    : $self->SUPER::get_commit_message ($log);
}

sub run {
    my ($self, $src, $dst) = @_;
    my $merge;
    die loc("repos paths mismatch") unless $src->same_repos ($dst);
    my $repos = $src->{repos};
    my $fs = $repos->fs;
    my $yrev = $fs->youngest_rev;

    if ($self->{sync}) {
        require SVK::Command::Sync;
        my $sync = SVK::Command::Sync->new;
        %$sync = (%$self, %$sync);
	my (undef, $m) = resolve_svm_source($repos, find_svm_source($repos, $src->{path}));
        if ($m->{target_path}) {
            $sync->run($self->arg_depotpath('/' . $src->depotname .  $m->{target_path}));
            $src->refresh_revision;
        }
    }

    if ($dst->root ($self->{xd})->check_path ($dst->path) != $SVN::Node::dir) {
	$src->anchorify; $dst->anchorify;
    }

    if ($self->{auto}) {
	die loc("No need to track rename for smerge\n")
	    if $self->{track_rename};
	# XXX: these should come from parse_arg
	$src->normalize; $dst->normalize;
	$merge = SVK::Merge->auto (%$self, repos => $repos, target => '',
				   ticket => !$self->{no_ticket},
				   src => $src, dst => $dst);
	print $merge->info;
    }
    else {
	die loc("Incremental merge not supported\n") if $self->{incremental};
	die loc("Revision required\n") unless $self->{revspec};
	my ($baserev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/
	    or die loc("Revision must be N:M\n");
	$src->{revision} = $torev;
	$merge = SVK::Merge->new
	    (%$self, repos => $repos, src => $src, dst => $dst,
	     base => $src->new (revision => $baserev), target => '');
    }

    $self->get_commit_message ($self->{log} ? $merge->log(1) : '')
	unless $dst->{copath};

    $merge->{notify} = SVK::Notify->new_with_report
	($dst->{report}, '', 1) if $dst->{copath};

    if ($self->{incremental} && !$self->{check_only}) {
	die loc ("Not possible to do incremental merge without a merge ticket.\n")
	    if $self->{no_ticket};
	print loc ("-m ignored in incremental merge\n") if $self->{message};
	my @rev;
	my $hist = $src->root->node_history ($src->{path});
	my $spool = SVN::Pool->new_default;
	while ($hist = $hist->prev (0)) {
	    my $rev = ($hist->location)[1];
	    last if $rev <= $merge->{fromrev};
	    unshift @rev, $rev;
	    $spool->clear;
	}
	for (@rev) {
	    $src->{revision} = $_;
	    $merge = SVK::Merge->auto (%$self, repos => $repos, ticket => 1,
				       src => $src, dst => $dst);
	    print '===> '.$merge->info;
	    $self->{message} = $merge->log (1);
	    last if $merge->run ($self->get_editor ($dst));
	    # refresh dst
	    $dst->{revision} = $fs->youngest_rev;
	    $spool->clear;
	}
    }
    else {
	print loc("Incremental merge not guaranteed even if check is successful\n")
	    if $self->{incremental};
	$merge->run ($self->get_editor ($dst));
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
 -m [--message] arg     : specify commit message ARG
 -C [--check-only]      : try operation but make no changes
 -I [--incremental]     : apply each change individually
 -a [--auto]            : merge from the previous merge point
 -l [--log]             : use logs of merged revisions as commit message
 -s [--sync]            : synchronize mirrored sources before update
 -t [--to]              : merge to the specified path
 -f [--from]            : merge from the specified path
 -S [--sign]            : sign this change
 --no-ticket            : do not record this merge point
 --track-rename         : track changes made to renamed node

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
