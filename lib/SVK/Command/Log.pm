package SVK::Command::Log;
use strict;
our $VERSION = '0.13';

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
    my ($repos, $rev) = @_;
    my $revprops = $repos->fs->revision_proplist ($rev);

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
    if ($self->{limit}) {
	my $pool = SVN::Pool->new_default;
	my $hist = $fs->revision_root ($fromrev)->node_history ($target->{path});
	while (($hist = $hist->prev ($self->{cross})) && $self->{limit}--) {
	    $pool->clear;
	    $torev = ($hist->location)[1];
	}
    }

    do_log ($target->{repos}, $target->{path}, $fromrev, $torev,
	    $self->{verbose}, $self->{cross}, 1);
    return;
}

sub do_log {
    my ($repos, $path, $fromrev, $torev, $verbose,
	$cross, $remote, $showhost, $output) = @_;
    $output ||= \*STDOUT;
    print $output ('-' x 70);
    print $output "\n";
    no warnings 'uninitialized';
    use Sys::Hostname;
    my ($host) = split ('\.', hostname, 2);
    $repos->get_logs ([$path], $fromrev, $torev, $verbose, !$cross,
		     sub { my ($paths, $rev, $author, $date, $message) = @_;
			   no warnings 'uninitialized';
			   print $output "r$rev".($showhost ? "\@$host" : '').
			       ($remote ? log_remote_rev($repos, $rev): '').
				   ":  $author | $date\n";
			   if ($paths) {
			       print $output loc("Changed paths:\n");
			       for (sort keys %$paths) {
				   my $entry = $paths->{$_};
				   print $output
				       '  '.$entry->action." $_".
					   ($entry->copyfrom_path ?
					    ' ' . loc("(from %1:%2)", $entry->copyfrom_path, $entry->copyfrom_rev) : ''
					   ).
					   "\n";
			       }
			   }
			   print $output "\n$message\n".('-' x 70). "\n";
		       });

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
