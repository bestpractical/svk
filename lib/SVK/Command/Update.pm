package SVK::Command::Update;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;

sub options {
    ('r|revision=i'   => 'rev',
     'N|nonrecursive' => 'nonrecursive');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_copath ($_)} @arg;
}

sub lock {
    my ($self, @arg) = @_;
    $self->lock_target ($_) for @arg;
}

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	my $update_target = SVK::Target->new
	    ( %$target,
	      path => $self->{update_target_path} || $target->{path},
	      revision => defined $self->{rev} ?
	      $self->{rev} : $target->{repos}->fs->youngest_rev,
	      copath => undef
	    );

	$self->do_update ($target, $update_target);
    }
    return;
}

sub do_update {
    my ($self, $cotarget, $update_target) = @_;
    my $xdroot = $cotarget->root ($self->{xd});
    # unanchorified
    my ($path, $copath) = @{$cotarget}{qw/path copath/};
    my $report = $update_target->{report};

    print loc("Syncing %1(%2) in %3 to %4.\n", @{$cotarget}{qw( depotpath path copath )},
	      $update_target->{revision});
    unless ($xdroot->check_path ($cotarget->{path}) == $SVN::Node::dir) {
	$cotarget->anchorify;
	$update_target->anchorify;
    }
    else {
	mkdir ($cotarget->{copath})
	    unless $self->{check_only};
    }

    my $merge = SVK::Merge->new
	(repos => $cotarget->{repos}, base => $cotarget, base_root => $xdroot,
	 no_recurse => $self->{nonrecursive}, report => $report,
	 src => $update_target, xd => $self->{xd}, check_only => $self->{check_only});
    $merge->run ($self->{xd}->get_editor (copath => $copath, path => $path,
					  oldroot => $xdroot, newroot => $update_target->root,
					  revision => $update_target->{revision},
					  anchor => $cotarget->{path},
					  target => $cotarget->{targets}[0] || '',
					  update => 1, check_only => $self->{check_only}));
}

1;

__DATA__

=head1 NAME

SVK::Command::Update - Bring changes from the repository into checkout copies

=head1 SYNOPSIS

 update [PATH...]

=head1 OPTIONS

 -r [--revision]:        revision
 -N [--nonrecursive]:    update non-recursively

=head1 DESCRIPTION

Synchronize checkout copies to revision given by -r or to HEAD
revision by deafult.

For each updated item a line will start with a character reporting the
action taken. These characters have the following meaning:

  A  Added
  D  Deleted
  U  Updated
  C  Conflict
  G  Merged
  g  Merged without actual change

A character in the first column signifies an update to the actual
file, while updates to the file's props are shown in the second
column.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
