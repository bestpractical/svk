package SVK::Command::Add;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 1;
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( $SEP is_symlink to_native);

sub options {
    ('q|quiet'		=> 'quiet');
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

    unless ($self->{recursive}) {
	die loc ("%1 already under version control.\n", $target->{report})
	    unless $target->{targets};
	# check for multi-level targets
	for (@{$target->{targets}}) {
	    # XXX: consolidate sep for targets
	    my ($parent) = m{^(.*)[/\Q$SEP\E]}o or next;
	    die loc ("Please add the parent directory '%1' first.\n", $parent)
		unless $self->{xd}{checkout}->
		    get ($target->copath ($parent))->{'.schedule'};
	}
    }

    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $target->root ($self->{xd}),
	  delete_verbose => 1,
	  unknown_verbose => $self->{recursive},
	  editor => SVK::Editor::Status->new
	  ( notify => SVK::Notify->new
	    ( cb_flush => sub {
		  my ($path, $status) = @_;
	          to_native($path, 'path');
		  my ($copath, $report) = map { SVK::Target->copath ($_, $path) }
		      @{$target}{qw/copath report/};

		  $target->contains_copath ($copath) or return;
		  die loc ("%1 already added.\n", $report)
		      if !$self->{recursive} && ($status->[0] eq 'R' || $status->[0] eq 'A');

		  return unless $status->[0] eq 'D';
		  lstat ($copath);
		  $self->_do_add ('R', $copath, $report, !-d _)
		      if -e _;
	      })),
	  cb_unknown => sub {
	      my ($editor, $path) = @_;
	      to_native($path, 'path');
	      my ($copath, $report) = map { SVK::Target->copath ($_, $path) }
	          @{$target}{qw/copath report/};
	      lstat ($copath);
	      $self->_do_add ('A', $copath, $report, !-d _);
	  },
	);
    return;
}

my %sch = (A => 'add', 'R' => 'replace');

sub _do_add {
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

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
