package SVK::Command::Propset;
use strict;
our $VERSION = '0.14';
use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;

sub parse_arg {
    my ($self, @arg) = @_;
    $self->usage if $#arg < 2;
    return (@arg[0,1], map {$self->arg_co_maybe ($_)} @arg[2..$#arg]);
}

sub lock {
    my $self = shift;
    $_->{copath} ? $self->lock_target ($_) : $self->lock_none
	for (@_[2..$#_]);
}

sub do_propset_direct {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);
    my $kind = $root->check_path ($arg{path});

    die loc("path %1 does not exist", $arg{path}) if $kind == $SVN::Node::none;

    my $edit = $self->get_commit_editor
	($root, sub { print loc("Committed revision %1.\n", $_[0]) }, '/', %arg);
    $edit->open_root();

    if ($kind == $SVN::Node::dir) {
	$edit->change_dir_prop ($arg{path}, $arg{propname}, $arg{propvalue});
    }
    else {
	$edit->change_file_prop ($arg{path}, $arg{propname}, $arg{propvalue});
    }

    $edit->close_edit();
}

sub do_propset {
    my ($self, $pname, $pvalue, $target) = @_;

    if ($target->{copath}) {
	$self->{xd}->do_propset
	    ( %$target,
	      propname => $pname,
	      propvalue => $pvalue,
	    );
    }
    else {
	return unless $self->check_mirrored_path ($target);
	$self->get_commit_message ();
	$self->do_propset_direct ( author => $ENV{USER},
				   %$target,
				   propname => $pname,
				   propvalue => $pvalue,
				   message => $self->{message},
				 );
    }
}

sub run {
    my ($self, $pname, $pvalue, @targets) = @_;
    $self->do_propset ($pname, $pvalue, $_) for @targets;
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Propset - Set a property on path

=head1 SYNOPSIS

    propset PROPNAME PROPVAL [PATH|DEPOTPATH...]

=head1 OPTIONS

  -m [--message] message:	Commit message
  -C [--check-only]:	Needs description
  -s [--sign]:	Needs description
  -force:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
