package SVK::Command::Revert;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 0;
use SVK::XD;
use SVK::Util qw( slurp_fh is_symlink );
use SVK::I18N;

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_condensed (@arg);
}

sub lock {
    $_[0]->lock_target ($_[1]);
}

sub run {
    my ($self, $target) = @_;
    my $xdroot = $self->{xd}->xdroot (%$target);

	$self->{xd}->checkout_delta
	    ( %$target,
	      xdroot => $xdroot,
	      depth => $self->{recursive} ? undef : 0,
	      delete_verbose => 1,
	      absent_verbose => 1,
	      nodelay => 1,
	      cb_conflict => \&SVK::Editor::Status::conflict,
	      cb_unknown => sub {
		  my ($path, $copath) = @_;
		  return unless $target->contains_copath ($copath);
		  print loc("%1 is not versioned; ignored.\n",
			    $target->report_copath ($copath));
		  return;
	      },
	      editor => SVK::Editor::Status->new
	      ( notify => SVK::Notify->new
		( cb_flush => sub {
		      my ($path, $status) = @_;
		      my $st = $status->[0];
		      my $dpath = $path ? "$target->{path}/$path" : $target->{path};
		      my $copath = $target->copath ($path);

                      if ($st =~ /[DMRC!]/) {
			  # conflicted items do not necessarily exist
			  return $self->do_unschedule ($target, $copath)
			      if ($st eq 'C' || $status->[2]) && !$xdroot->check_path ($dpath);
                          return $self->do_revert($target, $copath, $dpath, $xdroot);
                      }

                      if ($target->{targets}) {
                          # Check that we are not reverting parents
                          $target->contains_copath ($copath) or return;
                      }
                      $self->do_unschedule($target, $copath);
		  },
		),
	      ));

    return;
}

sub do_revert {
    my ($self, $target, $copath, $dpath, $xdroot) = @_;

    # XXX: need to respect copied resources
    my $kind = $xdroot->check_path ($dpath);
    if ($kind == $SVN::Node::dir) {
	mkdir $copath unless -e $copath;
    }
    else {
	# XXX: PerlIO::via::symlink should take care of this.
	# It doesn't overwrite existing file or close.
	unlink $copath;
	my $fh = SVK::XD::get_fh ($xdroot, '>', $dpath, $copath);
	my $content = $xdroot->file_contents ($dpath);
	slurp_fh ($content, $fh);
	close $fh or die $!;
	# XXX: get_fh should open file with proper permission bit
	$self->{xd}->fix_permission ($copath, 1)
	    if defined $xdroot->node_prop ($dpath, 'svn:executable');
    }
    $self->do_unschedule($target, $copath);
}

sub do_unschedule {
    my ($self, $target, $copath) = @_;
    $self->{xd}{checkout}->store ($copath, { $self->_schedule_empty,
					     '.conflict' => undef });
    print loc("Reverted %1\n", $target->report_copath ($copath));

}

1;

__DATA__

=head1 NAME

SVK::Command::Revert - Revert changes made in checkout copies

=head1 SYNOPSIS

 revert PATH...

=head1 OPTIONS

 -R [--recursive]       : descend recursively

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

