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
        'view'    => 'view',
        'dump'    => 'dump',
        'regen'   => 'regen',
        'update'  => 'update',
        'test'    => 'test',
        'apply'   => 'apply',
        'delete'  => 'delete',
        'list'    => 'list',
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

 patch --list
 patch --view PATCHNAME
 patch --regen PATCHNAME
 patch --update PATCHNAME
 patch --apply PATCHNAME [DEPOTPATH | PATH] [-- MERGEOPTIONS]
 patch --delete PATCHNAME

=head1 OPTIONS

 None

=head1 DESCRIPTION

Note that patches are created with C<commit -P> or C<smerge -P>.

A patch name of C<-> refers to the standard input and output.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
