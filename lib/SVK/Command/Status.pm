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
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return $self->arg_condensed (@arg);
}

sub run {
    my ($self, $target) = @_;
    my $xdroot = $self->{xd}->xdroot (%$target);
    my $report = $target->{report};
    $report .= '/' if $report;
    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $xdroot,
	  nodelay => 1,
	  delete_verbose => 1,
	  editor => SVK::Editor::Status->new (
	      report => $target->{report},
              ignore_absent => $self->{quiet},
	      notify => SVK::Notify->new_with_report ($target->{report}, undef, 1)
	  ),
	  cb_conflict => \&SVK::Editor::Status::conflict,
	  cb_obstruct => \&SVK::Editor::Status::obstruct,
	  $self->{recursive} ? () : (depth => 1),
	  $self->{no_ignore} ?
              (cb_ignored =>
                 sub { my $path = abs2rel($_[1],
                                          $target->{copath} => 
                                            length($report) ? $report : undef
                                         );
                       print "I   $path\n"
                 }
              )              :
              (),
	  $self->{quiet} ?
              ()         :
              (cb_unknown =>
                 sub { my $path = abs2rel($_[1],
                                          $target->{copath} => 
                                            length($report) ? $report : undef
                                         );
                       print "?   $path\n"
                 }
              )
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

The working copy path, which starts in the fourth column is always
the final field, so it can include spaces.

Example output:

  svk status
   M  bar.c
  A + qax.c

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
