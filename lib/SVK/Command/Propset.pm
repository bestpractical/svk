package SVK::Command::Propset;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Commit SVK::Command::Proplist );
use constant opt_recursive => 0;
use SVK::Util qw ( abs2rel );
use SVK::XD;
use SVK::I18N;

sub options {
    ($_[0]->SUPER::options,
     'K|keep-local' => 'keep',
     'r|revision=i' => 'rev',
     'revprop' => 'revprop',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if @arg < 2;
    push @arg, ('') if @arg == 2;
    return (@arg[0,1], map {$self->_arg_revprop ($_)} @arg[2..$#arg]);
}

sub lock {
    my $self = shift;
    $_->{copath} ? $self->lock_target ($_) : $self->lock_none
	for (@_[2..$#_]);
}

sub do_propset_direct {
    my ($self, $target, $propname, $propvalue) = @_;

    if ($self->{revprop}) {
	my $fs = $target->{repos}->fs;
        my $rev = (defined($self->{rev}) ? $self->{rev} : $target->{revision});
        $fs->change_rev_prop ($rev, $propname => $propvalue);
        print loc("Property '%1' set on repository revision %2.\n", $propname, $rev);
        return;
    }

    my $root = $target->root;
    my $kind = $root->check_path ($target->path);

    die loc("path %1 does not exist.\n", $target->path) if $kind == $SVN::Node::none;

    my ($anchor, $editor) = $self->get_dynamic_editor ($target);
    my $func = $kind == $SVN::Node::dir ? 'change_dir_prop' : 'change_file_prop';
    my $path = abs2rel ($target->path, $anchor => undef, '/');

    if ($kind == $SVN::Node::dir) {
	if ($anchor eq $target->path) {
	    $editor->change_dir_prop ($editor->{_root_baton}, $propname, $propvalue);
	}
	else {
	    my $baton = $editor->open_directory ($path, 0, $target->{revision});
	    $editor->change_dir_prop ($baton, $propname, $propvalue);
	    $editor->close_directory ($baton);
	}
    }
    else {
	my $baton = $editor->open_file ($path, 0, $target->{revision});
	$editor->change_file_prop ($baton, $propname, $propvalue);
	$editor->close_file ($baton, undef);
    }
    $self->adjust_anchor ($editor)
	unless $anchor eq $target->path;
    $self->finalize_dynamic_editor ($editor);
    return;
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
	# XXX: forbid special props on mirror anchor
	$self->get_commit_message () unless $self->{revprop};
	$self->do_propset_direct ( $target, $pname => $pvalue );
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

 propset PROPNAME PROPVAL [DEPOTPATH | PATH...]

=head1 OPTIONS

 -m [--message] arg     : specify commit message ARG
 -C [--check-only]      : try operation but make no changes
 -S [--sign]            : sign this change
 -R [--recursive]       : descend recursively
 -r [--revision] arg    : act on revision ARG instead of the head revision
 -P [--patch] arg       : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 --revprop              : operate on a revision property (use with -r)
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
