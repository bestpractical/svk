package SVK::Command::Revert;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::Util qw( slurp_fh is_symlink );
use SVK::I18N;

sub options {
    ('R|recursive'	=> 'rec');
}

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

    if ($self->{rec}) {
	$self->{xd}->checkout_delta
	    ( %$target,
	      xdroot => $xdroot,
	      delete_verbose => 1,
	      absent_verbose => 1,
	      editor => SVK::Editor::Status->new
	      ( notify => SVK::Notify->new
		( cb_flush => sub {
		      my ($path, $status) = @_;
		      my $st = $status->[0];
		      my $dpath = $path ? "$target->{path}/$path" : $target->{path};
		      my $copath = $target->copath ($path);

                      if ($st =~ /[DMR!]/) {
                          return $self->do_revert($copath, $dpath, $xdroot);
                      }

                      if ($target->{targets}) {
                          # Check that we are not reverting parents
                          $target->contains_copath ($copath) or return;
                      }

                      $self->do_unschedule($copath);
		  },
		),
	      ));
    }
    elsif ($target->{targets}) {
	$self->revert_item($target->copath ($_), "$target->{path}/$_", $xdroot)
	    for @{$target->{targets}};
    }
    else {
	$self->revert_item($target->{copath}, $target->{path}, $xdroot);
    }
    return;
}

sub revert_item {
    my ($self, $copath, $dpath, $xdroot) = @_;

    my $schedule = $self->{xd}{checkout}->get ($copath)->{'.schedule'};

    if ($schedule and $schedule ne 'delete') {
	$self->do_unschedule($copath);
    }
    else {
	# XXX - Should inhibit the "Reverted %1" message if nothing changed
	$self->do_revert($copath, $dpath, $xdroot);
    }
}

sub do_revert {
    my ($self, $copath, $dpath, $xdroot) = @_;

    # XXX: need to respect copied resources
    my $kind = $xdroot->check_path ($dpath);
    if ($kind == $SVN::Node::none) {
	print loc("%1 is not versioned; ignored.\n", $copath);
	return;
    }
    if ($kind == $SVN::Node::dir) {
	mkdir $copath unless -e $copath;
    }
    else {
	# XXX: PerlIO::via::symlink should take care of this
	unlink $copath if is_symlink($copath);
	my $fh = SVK::XD::get_fh ($xdroot, '>', $dpath, $copath);
	my $content = $xdroot->file_contents ($dpath);
	slurp_fh ($content, $fh);
	close $fh or die $!;
	# XXX: get_fh should open file with proper permission bit
	$self->{xd}->fix_permission ($copath, 1)
	    if defined $xdroot->node_prop ($dpath, 'svn:executable');
    }
    $self->do_unschedule($copath);
}

sub do_unschedule {
    my ($self, $copath) = @_;
    $self->{xd}{checkout}->store ($copath, { $self->_schedule_empty,
					     '.conflict' => undef });
    print loc("Reverted %1\n", $copath);
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

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

