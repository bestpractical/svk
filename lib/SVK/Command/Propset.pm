package SVK::Command::Propset;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Commit SVK::Command::Proplist );
use constant opt_recursive => 0;
use SVK::Util qw ( abs2rel );
use SVK::XD;
use SVK::I18N;

sub options {
    ($_[0]->SUPER::options,
     'r|revision=i' => 'rev',
     'revprop' => 'revprop',
     'q|quiet' => 'quiet',
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
    my @paths = @_[2..$#_];
    return unless grep {$_->copath} @paths;
    $self->lock_target ($self->arg_condensed (map {$_->{report}} @_[2..$#_]));
}

sub do_propset_direct {
    my ($self, $target, $propname, $propvalue) = @_;

    if ($self->{revprop}) {
	my $fs = $target->{repos}->fs;
        my $rev = (defined($self->{rev}) ? $self->{rev} : $target->{revision});
        $fs->change_rev_prop ($rev, $propname => $propvalue);
	unless ($self->{quiet}) {
	    if (defined $propvalue) {
		print loc("Property '%1' set on repository revision %2.\n",
		    $propname, $rev);
	    } else {
		print loc("Property '%1' deleted from repository revision %2.\n",
		    $propname, $rev);
	    }
	}
        return;
    }

    $target->normalize; # so find_remove_rev is used with right revision.
    my $root = $target->root;
    my $kind = $root->check_path ($target->path);

    die loc("path %1 does not exist.\n", $target->path) if $kind == $SVN::Node::none;

    my ($anchor, $editor) = $self->get_dynamic_editor ($target);
    my $func = $kind == $SVN::Node::dir ? 'change_dir_prop' : 'change_file_prop';
    my $path = abs2rel ($target->path, $anchor => undef, '/');

    my $m = $self->under_mirror ($target);
    my $rev = $target->{revision};
    $rev = $m->find_remote_rev ($rev) if $m;
    if ($kind == $SVN::Node::dir) {
	if ($anchor eq $target->path) {
	    $editor->change_dir_prop ($editor->{_root_baton}, $propname, $propvalue);
	}
	else {
	    my $baton = $editor->open_directory ($path, 0, $rev);
	    $editor->change_dir_prop ($baton, $propname, $propvalue);
	    $editor->close_directory ($baton);
	}
    }
    else {
	my $baton = $editor->open_file ($path, 0, $rev);
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
	die loc("-r not allowed for propset copath.\n")
	    if $self->{rev};
	# verify the content is not with mixed line endings.
	if ($pname eq 'svn:eol-style') {
	    my $xdroot = $target->root ($self->{xd});
	    my $fh = SVK::XD::get_fh ($xdroot, '<', $target->{path}, $target->{copath},
				      { 'svn:eol-style' => $pvalue }, '',
				      undef, 1);
	    eval {
		local $/ = \16384;
		while (<$fh>) { };
	    };
	    if ($@ =~ m/Mixed/) {
		die loc ("File %1 has inconsistent newlines.\n", $target->{report});
	    }
	    elsif ($@) {
		die $@;
	    }
	}

	$self->{xd}->do_propset
	    ( %$target,
	      propname => $pname,
	      propvalue => $pvalue,
	      quiet => $self->{quiet},
	    );
    }
    else {
	# XXX: forbid special props on mirror anchor
	die loc ("Can't set svn:eol-style on depotpath.\n")
	    if $pname eq 'svn:eol-style';
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

 -R [--recursive]       : descend recursively
 -r [--revision] REV    : act on revision REV instead of the head revision
 --revprop              : operate on a revision property (use with -r)
 -m [--message] MESSAGE : specify commit message MESSAGE
 -F [--file] FILENAME   : read commit message from FILENAME
 --template             : use the specified message as the template to edit
 --encoding ENC         : treat -m/-F value as being in charset encoding ENC
 -P [--patch] NAME      : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -C [--check-only]      : try operation but make no changes
 -q [--quiet]           : print as little as possible
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
