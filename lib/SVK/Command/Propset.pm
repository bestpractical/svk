package SVK::Command::Propset;
use strict;
our $VERSION = '0.11';
use base qw( SVK::Command::Commit );
use SVK::XD;

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

    die "path $arg{path} does not exist" if $kind == $SVN::Node::none;

    my $edit = $self->get_commit_editor
	($root, sub { print "Committed revision $_[0].\n" }, '/', %arg);
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

=head1 NAME

propset - Set a property on path.

=head1 SYNOPSIS

    propset PROPNAME PROPVAL [PATH|DEPOTPATH...]

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
