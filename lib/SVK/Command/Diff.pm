package SVK::Command::Diff;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw(get_anchor);
use SVK::Editor::Diff;

sub options {
    ("v|verbose"    => 'verbose',
     "r|revision=s" => 'revspec');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_co_maybe ($_)} @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target, $target2) = @_;
    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my ($oldroot, $newroot, $cb_llabel, $report);
    my ($r1, $r2);
    ($r1, $r2) = $self->{revspec} =~ m/^(\d+)(?::(\d+))?$/ if $self->{revspec};

    # translate to target and target2
    if ($target2) {
	if ($target->{copath}) {
	    die loc("invalid arguments");
	}
	if ($target2->{copath}) {
	    die loc("invalid arguments") if $target->{copath};
	    # prevent oldroot being xdroot below
	    $r1 ||= $yrev;
	}
    }
    else {
	delete $target->{copath} if $r1 && $r2;
	if ($target->{copath}) {
	    %$target2 = %$target;
	    delete $target->{copath};
	    $report = $target->{report};
	}
	else {
	    # XXX: require revspec;
	    %$target2 = %$target;
	}
    }

    if ($target2->{copath}) {
	$newroot = $self->{xd}->xdroot (%$target2);
	$oldroot = $newroot unless $r1;
	$cb_llabel =
	    sub { my ($rpath) = @_;
		  'revision '.($r1 ||
			       $self->{xd}{checkout}->get ("$target2->{copath}/$rpath")->{revision});
	      },
    }

    $r1 ||= $yrev, $r2 ||= $yrev;
    $oldroot ||= $fs->revision_root ($r1);
    $newroot ||= $fs->revision_root ($r2);

    my $editor = SVK::Editor::Diff->new
	( cb_basecontent =>
	  sub { my ($rpath) = @_;
		my $base = $oldroot->file_contents ("$target->{path}/$rpath");
		return $base;
	    },
	  cb_baseprop =>
	  sub { my ($rpath, $pname) = @_;
		return $oldroot->node_prop ("$target->{path}/$rpath", $pname);
	    },
	  $cb_llabel ? (cb_llabel => $cb_llabel) : (llabel => "revision $r1"),
	  rlabel => $target2->{copath} ? 'local' : "revision $r2",
	  external => $ENV{SVKDIFF},
	  $target->{path} ne $target2->{path} ?
	  ( lpath  => $target->{path},
	    rpath  => $target2->{path} ) : (),
	);

    if ($target2->{copath}) {
	if ($newroot->check_path ($target2->{path}) == $SVN::Node::file) {
	    my $tgt;
	    ($target2->{path}, $tgt) = get_anchor (1, $target2->{path});
	    ($target->{path}, $target2->{copath}) =
		get_anchor (0, $target->{path}, $target2->{copath});
	    $target2->{targets} = [$tgt];
	    $report = (get_anchor (0, $report))[0].'/' if defined $report;
	}
	else {
	    $report .= '/' if $report && $report !~ m|/$|;
	}
	$editor->{report} = $report;
	$self->{xd}->checkout_delta
	    ( %$target2,
	      base_root => $oldroot,
	      base_path => $target->{path},
	      xdroot => $newroot,
	      editor => $editor,
	    );
    }
    else {
	my $tgt = '';
	if ($newroot->check_path ($target2->{path}) == $SVN::Node::file) {
	    ($target->{path}, $tgt) =
		get_anchor (1, $target->{path});
	    $report = (get_anchor (0, $report))[0].'/' if defined $report;
	}
	$editor->{report} = $report;
	SVN::Repos::dir_delta ($oldroot->isa ('SVK::XD::Root') ? $oldroot->[1] : $oldroot,
			       $target->{path}, $tgt,
			       $newroot, $target2->{path},
			       $editor, undef,
			       1, 1, 0, 1);
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Diff - Display diff between revisions or checkout copies

=head1 SYNOPSIS

    diff [-r REV] [PATH]
    diff -r N:M DEPOTPATH
    diff DEPOTPATH1 DEPOTPATH2
    diff DEPOTPATH PATH

=head1 OPTIONS

  -r [--revision] rev|old:new :	Needs description
  -v [--verbose]:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
