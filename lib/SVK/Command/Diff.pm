package SVK::Command::Diff;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 1;
use SVK::I18N;
use autouse 'SVK::Util' => qw(get_anchor);

sub options {
    ("v|verbose"    => 'verbose',
     "s|summarize"  => 'summarize',
     "r|revision=s@" => 'revspec');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_co_maybe ($_)} @arg;
}

# XXX: need to handle peg revisions, ie
# -r N PATH@M means the node PATH@M at rev N
sub run {
    my ($self, $target, $target2) = @_;
    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my ($oldroot, $newroot, $cb_llabel, $report);
    my ($r1, $r2) = $self->resolve_revspec($target,$target2);

    # translate to target and target2
    if ($target2) {
	if ($target->{copath}) {
	    die loc("Invalid arguments.\n") if !$target2->{copath};
            $self->run($_) foreach @_[1..$#_];
            return;
	}
	if ($target2->{copath}) {
	    die loc("Invalid arguments.\n") if $target->{copath};
	    # prevent oldroot being xdroot below
	    $r1 ||= $yrev;
	    # diff DEPOTPATH COPATH require DEPOTPATH to exist
	    die loc("path %1 does not exist.\n", $target->{report})
		if $fs->revision_root ($r1)->check_path ($target->{path}) == $SVN::Node::none;
	}
    }
    else {
	$target->as_depotpath if $r1 && $r2;
	if ($target->{copath}) {
	    $target = $self->arg_condensed($target->{report});
	    $target2 = $target->new;
	    $target->as_depotpath;
	    $report = $target->{report};
	}
	else {
	    # XXX: require revspec;
	    $target2 = $target->new;
	}
    }

    if ($target2->{copath}) {
	$newroot = $target2->root ($self->{xd});
	$oldroot = $newroot unless $r1;
	my $lrev = $r1; # for the closure
	$cb_llabel =
	    sub { my ($rpath) = @_;
		  'revision '.($lrev ||
			       $self->{xd}{checkout}->get ($target2->copath ($rpath))->{revision});
	      },
    }

    $r1 ||= $yrev, $r2 ||= $yrev;
    $oldroot ||= $fs->revision_root ($r1);
    $newroot ||= $fs->revision_root ($r2);

    unless ($target2->{copath}) {
	die loc("path %1 does not exist.\n", $target2->{report})
	    if $fs->revision_root ($r2)->check_path ($target2->{path}) == $SVN::Node::none;
    }

    my $editor = $self->{summarize} ?
	SVK::Editor::Status->new
	: SVK::Editor::Diff->new
	( cb_basecontent =>
	  sub { my ($rpath, $pool) = @_;
		my $base = $oldroot->file_contents ("$target->{path}/$rpath", $pool);
		return $base;
	    },
	  cb_baseprop =>
	  sub { my ($rpath, $pname, $pool) = @_;
		my $path = "$target->{path}/$rpath";
		return $oldroot->check_path ($path, $pool) == $SVN::Node::none ?
		    undef : $oldroot->node_prop ($path, $pname, $pool);
	    },
	  $cb_llabel ? (cb_llabel => $cb_llabel) : (llabel => "revision $r1"),
	  rlabel => $target2->{copath} ? 'local' : "revision $r2",
	  external => $ENV{SVKDIFF},
	  $target->{path} ne $target2->{path} ?
	  ( lpath  => $target->{path},
	    rpath  => $target2->{path} ) : (),
	  # XXX: for delete_entry, clean up these
	  oldtarget => $target, oldroot => $oldroot,
	);

    my $kind = $oldroot->check_path ($target->{path});
    if ($target2->{copath}) {
	if ($kind != $SVN::Node::dir) {
	    my $tgt;
	    ($target2->{path}, $tgt) = get_anchor (1, $target2->{path});
	    ($target->{path}, $target2->{copath}) =
		get_anchor (0, $target->{path}, $target2->{copath});
	    $target2->{targets} = [$tgt];
	    ($report) = get_anchor (0, $report) if defined $report;
	}
	$editor->{report} = $report;
	$self->{xd}->checkout_delta
	    ( %$target2,
	      expand_copy => 1,
	      base_root => $oldroot,
	      base_path => $target->{path},
	      xdroot => $newroot,
	      editor => $editor,
	      $self->{recursive} ? () : (depth => 1),
	    );
    }
    else {
	my $tgt = '';
	die loc("path %1 does not exist.\n", $target->{report})
	    if $kind == $SVN::Node::none;

	if ($kind != $SVN::Node::dir) {
	    ($target->{path}, $tgt) =
		get_anchor (1, $target->{path});
	    ($report) = get_anchor (0, $report) if defined $report;
	}
	$editor->{report} = $report;
	$self->{xd}->depot_delta
	    ( oldroot => $oldroot,
	      oldpath => [$target->{path}, $tgt],
	      newroot => $newroot,
	      newpath => $target2->{path},
	      editor => $editor,
	      $self->{recursive} ? () : (no_recurse => 1),
	    );
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Diff - Display diff between revisions or checkout copies

=head1 SYNOPSIS

 diff [-r REV] [PATH...]
 diff -r N[:M] DEPOTPATH
 diff DEPOTPATH1 DEPOTPATH2
 diff DEPOTPATH PATH

=head1 OPTIONS

 -r [--revision] arg    : ARG (some commands also take ARG1:ARG2 range)

                          A revision argument can be one of:

                          "HEAD"       latest in repository
                          NUMBER       revision number
                          NUM1:NUM2    revision range

                          Given negative NUMBER means "HEAD"+NUMBER.
                          (Counting backwards)

 -s [--summarize]       : show summary only
 -v [--verbose]         : print extra information
 -N [--non-recursive]   : do not descend recursively

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
