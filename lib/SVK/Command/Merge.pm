package SVK::Command::Merge;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Delay;
use SVK::Command::Log;
use SVK::Merge;
use SVK::Util qw (get_buffer_from_editor find_svm_source svn_mirror);

sub options {
    ($_[0]->SUPER::options,
     'a|auto'		=> 'auto',
     'l|log'		=> 'log',
     'remoterev'	=> 'remoterev',
     'host=s'   	=> 'host',
     'I|incremental'	=> 'incremental',
     'no-ticket'	=> 'no_ticket',
     'r|revision=s'	=> 'revspec');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0 || $#arg > 1;
    return ($self->arg_depotpath ($arg[0]), $self->arg_co_maybe ($arg[1] || ''));
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

    if ($self->{auto}) {
	# XXX: these should come from parse_arg
	$src->normalize; $dst->normalize;
	$merge = SVK::Merge->auto (%$self, repos => $repos,
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
	     base => SVK::Target->new (%$src, revision => $baserev));
    }

    $self->get_commit_message ($self->{log} ? $merge->log : '')
	unless $dst->{copath};

    $merge->{report} = $dst->{report} if $dst->{copath};

    if ($self->{incremental} && !$self->{check_only}) {
	die loc ("Not possible to do incremental merge without merge ticket.\n")
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

merge -r N:M DEPOTPATH [PATH]\r
merge -r N:M DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

 -r [--revision] rev:       revision
 -m [--message] message:    commit message
 -C [--check-only]:         don't perform actual writes
 -I [--incremental]:        apply changes individually
 -a [--auto]:               automatically find merge points
 -l [--log]:                brings the logs of merged revs to the message buffer
 --no-ticket:               don't associate the ticket tracking merge history
 --force:                   Needs description
 -s [--sign]:               Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
