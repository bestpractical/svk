package SVK::Command::Delete;
use strict;
our $VERSION = '0.14';
use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;

sub parse_arg {
    my ($self, @arg) = @_;
    $self->usage if $#arg < 0;
    my $target;
    if ($#arg == 0) {
	$target = $self->arg_co_maybe ($arg[0]);
	return $target unless $target->{copath};
    }
    return $self->arg_condensed (@arg);
}

sub lock {
    my ($self, $target) = @_;
    $target->{copath} ? $self->lock_target ($target) : $self->lock_none;
}

sub do_delete_direct {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);
    my $kind = $root->check_path ($arg{path});

    die loc("path %1 does not exist", $arg{path}) if $kind == $SVN::Node::none;

    my $edit = $self->get_commit_editor
	($root, sub { print loc("Committed revision %1.\n", $_[0]) }, '/', %arg);
    $edit->open_root();

    $edit->delete_entry ($arg{path});
    if ($self->svn_mirror &&
	(my ($m, $mpath) = SVN::Mirror::is_mirrored ($arg{repos},
						     $arg{path}))) {
	my $uuid = $root->node_prop ($arg{path}, 'svm:uuid');
	$edit->change_dir_prop ('', "svm:mirror:$uuid:".($m->{source_path} || '/'), undef);
    }

    $edit->close_edit();
}

sub run {
    my ($self, $target) = @_;

    if ($target->{copath}) {
	$self->{xd}->do_delete ( %$target );
    }
    else {
	$self->get_commit_message ();
	$self->do_delete_direct ( author => $ENV{USER},
				  %$target,
				  message => $self->{message},
				);
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Delete - Remove versioned item

=head1 SYNOPSIS

    delete [PATH...]
    delete [DEPOTPATH...]

=head1 OPTIONS

    -m [--message] message: commit message

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
