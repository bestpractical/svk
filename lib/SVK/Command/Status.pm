package SVK::Command::Status;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 1;
use SVK::XD;
use SVK::Editor::Status;
use SVK::Util qw( abs2rel );

sub options {
    ("q|quiet"    => 'quiet',
     "no-ignore"  => 'no_ignore',
     "v|verbose"  => 'verbose',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return $self->arg_condensed (@arg);
}

sub flush_print {
    my ($root, $target, $entry, $status, $baserev, $from_path, $from_rev) = @_;
    my ($crev, $author);
    my $fs = $root->fs;
    if ($from_path) {
	$from_path =~ s{^file://\Q$target->{repospath}\E}{};
        $crev = $fs->revision_root ($from_rev)->node_created_rev ($from_path);
	$author = $fs->revision_prop ($crev, 'svn:author');
	$baserev = '-';
    } elsif ($status->[0] =~ '[I?]') {
	$baserev = '';
	$crev = '';
	$author = ' ';
    } elsif ($status->[0] eq 'A') {
	$baserev = 0;
    } elsif ($status->[0] !~ '[!~]') {
        my $p = $target->{path};
	my $path = $p eq '/' ? "/$entry" : (length $entry ? "$p/$entry" : $p);
	$crev = $root->node_created_rev ($path);
	$author = $fs->revision_prop ($crev, 'svn:author');
    }

    my $report = $target->{report};
    my $newentry = length $entry
	? SVK::Target->copath ($report, $entry)
	: SVK::Target->copath ('', length $report ? $report : '.');
    no warnings 'uninitialized';
    print sprintf ("%1s%1s%1s %8s %8s %-12.12s \%s\n", @{$status}[0..2],
                   defined $baserev ? $baserev : '? ',
		   defined $crev ? $crev : '? ',
		   $author ? $author : ' ?',
                   $newentry);
}

sub run {
    my ($self, $target) = @_;
    my $xdroot = $self->{xd}->xdroot (%$target);
    my $report = $target->{report};
    $report .= '/' if $report;
    my $editor = SVK::Editor::Status->new (
	  report => $target->{report},
	  ignore_absent => $self->{quiet},
	  $self->{verbose} ?
	  (notify => SVK::Notify->new (
	       flush_baserev => 1,
	       flush_unchanged => 1,
	       cb_flush => sub { flush_print ($xdroot, $target, @_); }
	   )
	  )                :
	  (notify => SVK::Notify->new_with_report ($target->{report},
		undef, 1)
	  )
      );
    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $xdroot,
	  nodelay => 1,
	  delete_verbose => 1,
	  editor => $editor,
	  cb_conflict => \&SVK::Editor::Status::conflict,
	  cb_obstruct => \&SVK::Editor::Status::obstruct,
	  $self->{verbose} ?
	      (cb_unchanged => \&SVK::Editor::Status::unchanged
	      )            :
	      (),
	  $self->{recursive} ? () : (depth => 1),
	  $self->{no_ignore} ?
              (cb_ignored => \&SVK::Editor::Status::ignored
              )              :
              (),
	  $self->{quiet} ?
              ()         :
              (cb_unknown => \&SVK::Editor::Status::unknown)
	);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Status - Display the status of items in the checkout copy

=head1 SYNOPSIS

 status [PATH..]

=head1 OPTIONS

 -q [--quiet]           : do not display files not under version control
 --no-ignore            : disregard default and svn:ignore property ignores
 -N [--non-recursive]   : do not descend recursively
 -v [--verbose]         : print full revision information on every item

=head1 DESCRIPTION

Show pending changes in the checkout copy.

The first three columns in the output are each one character wide:

First column, says if item was added, deleted, or otherwise changed:

  ' '  no modifications
  'A' Added
  'C' Conflicted
  'D' Deleted
  'I' Ignored
  'M' Modified
  'R' Replaced
  '?' item is not under version control
  '!' item is missing (removed by non-svk command) or incomplete
  '~' versioned item obstructed by some item of a different kind

Second column, modifications of a file's or directory's properties:

  ' ' no modifications
  'C' Conflicted
  'M' Modified

Third column, scheduled commit will contain addition-with-history

  ' ' no history scheduled with commit
  '+' history scheduled with commit

Remaining fields are variable width and delimited by spaces:
  The working revision (with -v)
  The last committed revision and last committed author (with -v)
  The working copy path is always the final field, so it can include spaces.

Example output:

  svk status
   M  bar.c
  A + qax.c

  svk status --verbose wc
   M        53        2 sally        wc/bar.c
            53       51 harry        wc/foo.c
  A +        -       ?   ?           wc/qax.c
            53       43 harry        wc/zig.c
            53       20 sally        wc

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
