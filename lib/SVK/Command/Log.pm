package SVK::Command::Log;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;

sub options {
    ('l|limit=i'	=> 'limit',
     'r|revision=s'	=> 'revspec',
     'x|cross'		=> 'cross',
     'v|verbose'	=> 'verbose');
}

sub log_remote_rev {
    # XXX: Use an api instead
    my ($fs, $rev) = @_;
    my $revprops = $fs->revision_proplist ($rev);

    my ($rrev) = map {$revprops->{$_}} grep {m/^svm:headrev:/} sort keys %$revprops;

    return $rrev ? " (orig r$rrev)" : '';
}

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_co_maybe (@arg);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target) = @_;

    my $fs = $target->{repos}->fs;
    my ($fromrev, $torev);
    ($fromrev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/
	or $fromrev = $torev = $self->{revspec}
	    if $self->{revspec};
    $fromrev ||= $fs->youngest_rev;
    $torev ||= 0;

    $self->{cross} ||= 0;

    my $sep = ('-' x 70)."\n";
    print $sep;
    _get_logs ($fs, $self->{limit} || -1, $target->{path}, $fromrev, $torev,
	       $self->{verbose}, $self->{cross},
	       sub {_show_log (@_, $sep, undef, '', 1)} );
    return;
}

sub _get_logs {
    my ($fs, $limit, $path, $fromrev, $torev, $verbose, $cross, $callback) = @_;
    my $reverse = ($fromrev < $torev);
    my @revs;
    ($fromrev, $torev) = ($torev, $fromrev) if $reverse;
    $torev = 1 if $torev < 1;

    my $docall = sub {
	my ($rev) = @_;
	my ($root, $changed, $props);
	$root = $fs->revision_root ($rev);
	$changed = $root->paths_changed if $verbose;
	$props = $fs->revision_proplist ($rev);
	$callback->($rev, $root, $changed, $props);
    };

    my $pool = SVN::Pool->new_default;
    my $hist = $fs->revision_root ($fromrev)->node_history ($path);
    while (($hist = $hist->prev ($cross)) && $limit--) {
	my $rev = ($hist->location)[1];
	last if $rev < $torev;
	$reverse ?  unshift @revs, $rev : $docall->($rev);
	$pool->clear;
    }

    if ($reverse) {
	$docall->($_), $pool->clear for @revs;
    }
}

my $chg;
$chg->[$SVN::Fs::PathChange::modify] = 'M';
$chg->[$SVN::Fs::PathChange::add] = 'A';
$chg->[$SVN::Fs::PathChange::delete] = 'D';
$chg->[$SVN::Fs::PathChange::replace] = 'R';

sub _show_log { 
    my ($rev, $root, $paths, $props, $sep, $output, $host, $remote) = @_;
    $output ||= select;
    my ($author, $date, $message) = @{$props}{qw/svn:author svn:date svn:log/};
    no warnings 'uninitialized';
    $output->print ("r$rev$host".
		    ($remote ? log_remote_rev($root->fs, $rev): '').
		    ":  $author | $date\n");
    if ($paths) {
	$output->print (loc("Changed paths:\n"));
	for (sort keys %$paths) {
	    my $entry = $paths->{$_};
	    my ($action, $propaction) = ($chg->[$entry->change_kind], ' ');
	    my ($copyfrom_rev, $copyfrom_path) = $action eq 'D' ? (-1) : $root->copied_from ($_);
	    $propaction = 'M' if $action eq 'M' && $entry->prop_mod;
	    $action = ' ' if $action eq 'M' && !$entry->text_mod;
	    $action = 'M' if $action eq 'A' && $copyfrom_path && $entry->text_mod;
	    $output->print (
		"  $action$propaction $_".
		    ($copyfrom_path ?
		     ' ' . loc("(from %1:%2)", $copyfrom_path, $copyfrom_rev) : ''
		    )."\n");
	}
    }
    $output->print ("\n$message\n$sep");
}

sub do_log {
    my ($repos, $path, $fromrev, $torev, $verbose,
	$cross, $remote, $showhost, $output, $sep) = @_;
    $output ||= \*STDOUT;
    print $output $sep if $sep;
    no warnings 'uninitialized';
    use Sys::Hostname;
    my ($host) = split ('\.', hostname, 2);
    $host = $showhost ? '@'.$host : '';
    _get_logs ($repos->fs, -1, $path, $fromrev, $torev, $verbose, $cross,
	       sub {_show_log (@_, $sep, $output, $host, $remote)} )
}

1;

__DATA__

=head1 NAME

SVK::Command::Log - Show log messages for revisions

=head1 SYNOPSIS

    log DEPOTPATH
    log PATH

=head1 OPTIONS

    -r [--revision]:        revision spec from:to
    -l [--limit]:           limit the number of revisions displayed
    -x [--cross]:           display cross copied nodes
    -v [--verbose]:         print changed path in changes

=head1 OPTIONS

  -r [--revision] arg:	Needs description
  -l [--limit] arg:	Needs description
  -x [--cross]:	Needs description
  -v [--verbose]:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
