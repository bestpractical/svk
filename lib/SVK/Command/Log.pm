package SVK::Command::Log;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;
use SVK::CommitStatusEditor;

sub options {
    ('l|limit=i'		=> 'limit',
     'r|revision=s'	=> 'revspec',
     'x|cross'		=> 'cross',
     'v|verbose'		=> 'verbose');
}

sub log_remote_rev {
    my ($repos, $rev) = @_;
    my $revprops = $repos->fs->revision_proplist ($rev);

    my ($rrev) = map {$revprops->{$_}} grep {m/^svm:headrev:/} keys %$revprops;

    return $rrev ? " (orig r$rrev)" : '';
}

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_co_maybe (@arg);
}

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
    my ($repos, $path, $fromrev, $torev, $verbose, $cross, $remote, $output)
	= @_;
    $output ||= \*STDOUT;
    print $output ('-' x 70);
    print $output "\n";
    $repos->get_logs ([$path], $fromrev, $torev, $verbose, !$cross,
		     sub { my ($paths, $rev, $author, $date, $message) = @_;
			   no warnings 'uninitialized';
			   print $output "r$rev".
			       ($remote ? log_remote_rev($repos, $rev): '').
				   ":  $author | $date\n";
			   if ($paths) {
			       print $output "Changed paths:\n";
			       for (sort keys %$paths) {
				   my $entry = $paths->{$_};
				   print $output
				       '  '.$entry->action." $_".
					   ($entry->copyfrom_path ?
					    " (from ".$entry->copyfrom_path.
					    ':'.$entry->copyfrom_rev.')' : ''
					   ).
					   "\n";
			       }
			   }
			   print $output "\n$message\n".('-' x 70). "\n";
		       });

}

1;

