package SVK::Command::Patch;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::Patch;
use SVK::Merge;
use SVK::Editor::Merge;
use SVK::I18N;
use SVK::Util qw (resolve_svm_source);
use SVK::Command::Log;

my %cmd = map {$_ => 1} qw/view dump update regen update test send delete apply/;
$cmd{delete} = $cmd{list} = 0;

sub options {
    ('depot=s' => 'depot');
}

sub lock { $_[0]->lock_none }

sub parse_arg {
    my ($self, $cmd, @arg) = @_;
    return unless $cmd && exists $cmd{$cmd};
    if ($cmd{$cmd}) {
	die loc ("Filename required.\n")
	    unless $arg[0];
	$arg[0] = $self->_load ($arg[0]);
    }
    return ($cmd, @arg);
}

sub view {
    my ($self, $patch) = @_;
    return $patch->view;
}

sub dump {
    my ($self, $patch) = @_;
    print YAML::Dump ($patch);
    return;
}

sub test {
    my ($self, $patch) = @_;

    if (my $conflicts = $patch->apply (1)) {
	print loc("%*(%1,conflict) found.\n", $conflicts);
	print loc("Please do a merge to resolve conflicts and regen the patch.\n");
    }

    return;
}

sub regen {
    my ($self, $patch) = @_;
    if (my $conflicts = $patch->regen) {
	# XXX: check empty too? probably already applied.
	return loc("%*(%1,conflict) found, patch aborted.\n", $conflicts)
    }
    $self->_store ($patch);
    return;

}

sub update {
    my ($self, $patch) = @_;
    if (my $conflicts = $patch->update) {
	# XXX: check empty too? probably already applied.
	return loc("%*(%1,conflict) found, update aborted.\n", $conflicts)
    }
    $self->_store ($patch);
    return;

}

sub delete {
    my ($self, $name) = @_;
    unlink $self->{xd}->patch_file ($name);
    return;
}

sub list {
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

sub apply {
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

1;

__DATA__

=head1 NAME

SVK::Command::Patch - Manage patches

=head1 SYNOPSIS

 patch list
 patch view PATCHNAME
 patch regen PATCHNAME
 patch update PATCHNAME
 patch apply PATCHNAME [DEPOTPATH | PATH] [-- MERGEOPTIONS]
 patch send PATCHNAME
 patch delete PATCHNAME

=head1 OPTIONS

 None

=head1 DESCRIPTION

Note that patches are created with C<commit -P> or C<smerge -P>.

A patch name of C<-> refers to the standard input and output.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
