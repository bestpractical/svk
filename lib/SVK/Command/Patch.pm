package SVK::Command::Patch;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::Patch;
use SVK::Merge;
use SVK::Editor::Merge;
use SVK::I18N;
use SVK::Util qw (resolve_svm_source);
use SVK::Command::Log;


sub options {
    (
        'view|cat'    => 'view',
        'dump'    => 'dump',
        'regen|regenerate'   => 'regen',
        'update|up'  => 'update',
        'test'    => 'test',
        'apply'   => 'apply',
        'delete|del|rm'  => 'delete',
        'list|ls'    => 'list',
        'depot=s' => 'depot'
    );
}

sub parse_arg {
    # always return help
    return;
}

sub _store {
    my ($self, $patch) = @_;
    $patch->store ($self->{xd}->patch_file ($patch->{name}));
}

sub _load {
    my ($self, $name) = @_;
    SVK::Patch->load (
        $self->{xd}->patch_file ($name),
        $self->{xd},
        ($self->{depot} || ''),
    );
}

sub run {
    my ($self, $func, @arg) = @_;
    $self->$func (@arg);
}

package SVK::Command::Patch::FileRequired;
use base qw/SVK::Command::Patch/;
use SVK::I18N;

sub parse_arg {
    my ($self, @arg) = @_;

	die loc ("Filename required.\n")
	    unless $arg[0];
	$arg[0] = $self->_load ($arg[0]);
    return @arg;
}

package SVK::Command::Patch::view;
use base qw/SVK::Command::Patch::FileRequired/;

sub run {
    my ($self, $patch) = @_;
    return $patch->view;
}

package SVK::Command::Patch::dump;

use base qw/SVK::Command::Patch::FileRequired/;

sub run {
    my ($self, $patch) = @_;
    print YAML::Dump ($patch);
    return;
}

package SVK::Command::Patch::test;

use base qw/SVK::Command::Patch::FileRequired/;
use SVK::I18N;

sub run {
    my ($self, $patch) = @_;

    if (my $conflicts = $patch->apply (1)) {
	print loc("%*(%1,conflict) found.\n", $conflicts);
	print loc("Please do a merge to resolve conflicts and regen the patch.\n");
    }

    return;
}

package SVK::Command::Patch::regen;
use SVK::I18N;

use base qw/SVK::Command::Patch::FileRequired/;

sub run {
    my ($self, $patch) = @_;
    if (my $conflicts = $patch->regen) {
	# XXX: check empty too? probably already applied.
	return loc("%*(%1,conflict) found, patch aborted.\n", $conflicts)
    }
    $self->_store ($patch);
    return;

}

package SVK::Command::Patch::update;
use SVK::I18N;

use base qw/SVK::Command::Patch::FileRequired/;

sub run {
    my ($self, $patch) = @_;
    if (my $conflicts = $patch->update) {
	# XXX: check empty too? probably already applied.
	return loc("%*(%1,conflict) found, update aborted.\n", $conflicts)
    }
    $self->_store ($patch);
    return;

}

package SVK::Command::Patch::delete;

use base qw/SVK::Command::Patch/;
sub parse_arg { undef }

sub run {
    my ($self, $name) = @_;
    unlink $self->{xd}->patch_file ($name);
    return;
}

package SVK::Command::Patch::list;

use base qw/SVK::Command::Patch/;

sub parse_arg { undef }
sub run {
    my ($self) = @_;
    my (undef, undef, $repos) = $self->{xd}->find_repos ('//', 1);
    opendir my $dir, $self->{xd}->patch_directory;
    foreach my $file (readdir ($dir)) {
	next if $file =~ /^\./;
	$file =~ s/\.patch$// or next;
	my $patch = $self->_load ($file);
	print "$patch->{name}\@$patch->{level}: \n";
    }
    return;
}

package SVK::Command::Patch::apply;
use SVK::I18N;

use base qw/SVK::Command::Patch::FileRequired/;

sub run {
    my ($self, $patch, @args) = @_;
    my $mergecmd = $self->command ('merge');
    $mergecmd->getopt (\@args);
    my $dst = $self->arg_co_maybe ($args[0] || '');
    $self->lock_target ($dst) if $dst->{copath};
    my $ticket;
    $mergecmd->get_commit_message ($patch->{log}) unless $dst->{copath};
    my $merge = SVK::Merge->new (%$mergecmd, dst => $dst, repos => $dst->{repos});
    $ticket = sub { $merge->get_new_ticket (SVK::Merge::Info->new ($patch->{ticket})) }
	if $patch->{ticket} && $dst->universal->same_resource ($patch->{target});
    $patch->apply_to ($dst, $mergecmd->get_editor ($dst),
		      resolve => $merge->resolver,
		      ticket => $ticket);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Patch - Manage patches

=head1 SYNOPSIS

 patch --ls    [--list]
 patch --cat   [--view]       PATCHNAME
 patch --regen [--regenerate] PATCHNAME
 patch --up    [--update]     PATCHNAME
 patch --apply                PATCHNAME [DEPOTPATH | PATH] [-- MERGEOPTIONS]
 patch --rm    [--delete]     PATCHNAME

=head1 OPTIONS

 None

=head1 DESCRIPTION

To create a patch, use C<commit -P> or C<smerge -P>.  To import a patch
that's sent to you by someone else, just drop it into the C<patch>
directory in your local svk repository. (That's usually C<~/.svk/>.)

svk patches are compatible with GNU patch. Extra svk-specific metadata
is stored in an encoded chunk at the end of the file.

A patch name of C<-> refers to the standard input and output.

=head1 INTRODUCTION

C<svk patch> command can help out on the situation where you want
to maintain your patchset to a given project.  It is used under the
situation that you have no direct write access to remote repository,
thus C<svk push> cannot be used.

Suppose you mirror project C<foo> to C<//mirror/foo>, create a local copy
on C<//local/foo>, and check out to C<~/dev/foo>. After you've done some
work, you type:

    svk commit -m "Add my new feature"

to commit changes from C<~/dev/foo> to C<//local/foo>. If you have commit
access to the upstream repository, you can submit your changes directly
like this:

    svk push //local/foo

Sometimes, it's useful to send a patch, rather than submit changes
directly, either because you don't have permission to commit to the
upstream repository or because you don't think your changes are ready
to be committed.

To create a patch containing the differences between C<//local/foo>
and C<//mirror/foo>, use this command:

    svk push -P Foo //local/foo

The C<-P> flag tells svk that you want to create a patch rather than
push the changes to the upstream repository.  C<-P> takes a single flag:
a patch name.  It probably makes sense to name it after the feature
implemented or bug fixed by the patch. Patch files you generate will be
created in the C<patch> subdirectory of your local svk repository.

Over time, other developers will make changes to project C<foo>. From
time to time, you may need to update your patch so that it still applies
cleanly. 

First, make sure your local branch is up to date with any changes made
upstream:

    svk pull //local/foo

Next, update your patch so that it will apply cleanly to the newest
version of the upstream repository:

    svk patch --update Foo

Finally, regenerate your patch to include other changes you've made on
your local branch since you created or last regenerated the patch:

    svk patch --regen Foo

To get a list of all patches your svk knows about, run:

    svk patch --list

To see the current version of a specific patch, run:
    
    svk patch --view Foo

When you're done with a patch and don't want it hanging around anymore,
run
    svk patch --delete Foo

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
