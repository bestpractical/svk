package SVK::Command::Revert;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::Util qw( slurp_fh );
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
    my $storeundef = {'.schedule' => undef,
		      scheduleanchor => undef,
		      '.copyfrom' => undef,
		      '.copyfrom_rev' => undef,
		      '.newprop' => undef};

    my $unschedule = sub {
	$self->{xd}{checkout}->store ($_[1], $storeundef);
	print loc("Reverted %1\n", $_[1]);
    };
    my $revert = sub {
	# XXX: need to repsect copied resources
	my $kind = $xdroot->check_path ($_[0]);
	if ($kind == $SVN::Node::none) {
	    print loc("%1 is not versioned; ignored.\n", $_[1]);
	    return;
	}
	if ($kind == $SVN::Node::dir) {
	    mkdir $_[1] unless -e $_[1];
	}
	else {
	    my $fh = SVK::XD::get_fh ($xdroot, '>', $_[0], $_[1]);
	    my $content = $xdroot->file_contents ($_[0]);
	    slurp_fh ($content, $fh);
	    close $fh;
	}
	$unschedule->(@_);
    };

    my $revert_item = sub {
	exists $self->{xd}{checkout}->get ($_[1])->{'.schedule'} ?
	    &$unschedule (@_) : &$revert (@_);
    };

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
		      my $copath = $path ? "$target->{copath}/$path" : $target->{copath};
		      if ($st eq 'M' || $st eq 'D' || $st eq '!' || $st eq 'R') {
			  $revert->($dpath, $copath);
		      }
		      else {
			  $unschedule->($dpath, $copath);
		      }
		  },
		),
	      ));
    }
    else {
	if ($target->{targets}) {
	    &$revert_item ("$target->{path}/$_", "$target->{copath}/$_")
		for @{$target->{targets}};
	}
	else {
	    &$revert_item ($target->{path}, $target->{copath});
	}
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Revert - Revert changes made in checkout copies

=head1 SYNOPSIS

    revert PATH...

=head1 OPTIONS

  -R [--recursive]:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

