package SVK::Command::Add;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( $SEP is_symlink );

sub options {
    ('N|non-recursive'	=> 'nrec',
     'q|quiet'		=> 'quiet');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return $self->arg_condensed (@arg);
}

sub lock {
    $_[0]->lock_target ($_[1]);
}

sub run {
    my ($self, $target) = @_;

    if ($self->{nrec} && $target->{targets}) {
	# check for multi-level targets
	die loc ("Please add the parent directory first.\n")
	    if grep { m{[/\Q$SEP\E]}o } @{$target->{targets}};
    }

    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $target->root ($self->{xd}),
	  delete_verbose => 1,
	  unknown_verbose => !$self->{nrec},
	  editor => SVK::Editor::Status->new
	  ( notify => SVK::Notify->new
	    ( cb_flush => sub {
		  my ($path, $status) = @_;
		  return unless $status->[0] eq 'D';
		  my ($copath, $report) = map { SVK::Target->copath ($_, $path) }
		      @{$target}{qw/copath report/};
		  lstat ($copath);
		  $self->do_add ('R', $copath, $report, !-d _)
		      if is_symlink || -e _;
	      })),
	  cb_unknown => sub {
	      $self->do_add ('A', $_[1], SVK::Target->copath ($target->{report}, $_[0]),
			     !-d $_[1]);
	  },
	);
}

my %sch = (A => 'add', 'R' => 'replace');

sub do_add {
    my ($self, $st, $copath, $report, $autoprop) = @_;
    $self->{xd}{checkout}->store ($copath,
				  { '.schedule' => $sch{$st},
				    $autoprop ?
				    ('.newprop'  => $self->{xd}->auto_prop ($copath)) : ()});
    print "$st   $report\n" unless $self->{quiet};

}

1;

__DATA__

=head1 NAME

SVK::Command::Add - Put files and directories under version control

=head1 SYNOPSIS

 add [PATH...]

=head1 OPTIONS

 -N [--non-recursive]   : do not descend recursively
 -q [--quiet]           : do not display changed nodes

=head1 DESCRIPTION

Put files and directories under version control, scheduling
them for addition to repository.  They will be added in next commit.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
