package SVK::Command::Patch;
use strict;
our $VERSION = '0.15';

use base qw( SVK::Command );
use SVK::XD;
use SVK::Patch;
use SVK::Merge;
use SVK::Editor::Merge;
use SVK::I18N;
use SVK::Util qw (resolve_svm_source);
use SVK::Command::Log;

sub lock { $_[0]->lock_none }

sub parse_arg {
    my ($self, $cmd, @arg) = @_;
    my @cmd = qw/create view dump update test send list delete/;
    $self->usage unless $cmd && (1 == grep {$_ eq $cmd} @cmd);
    $self->{cmd} = $cmd;
    return @arg;
}

sub create {
    my ($self, $name, @arg) = @_;
    # call svk::command::merge
    my $fname = "$self->{xd}{svkpath}/patch";
    mkdir ($fname);
    $fname .= "/$name.svkpatch";
    return "file $fname already exists, use $0 patch update $name instead\n"
	if -e $fname;

    my ($src, $dst) = map {$self->arg_depotpath ($_) } @arg;
    die loc("repos paths mismatch") unless $src->{repospath} eq $dst->{repospath};

    my $repos = $src->{repos};
    my $fs = $repos->fs;

    my $patch = SVK::Patch->new (name => $name, level => 0, _repos => $repos);
    $patch->from ($src->{path});
    # XXX: from/to should take rev too
    $patch->{source_rev} = 0;
    $patch->applyto ($dst->{path});

    $self->_do_update ($name, $patch);
}

sub view {
    my ($self, $name) = @_;
    my (undef, undef, $repos) = $self->{xd}->find_repos ('//', 1);
    my $patch = SVK::Patch->load ("$self->{xd}{svkpath}/patch/$name.svkpatch", $repos);

    $patch->view ($repos);
    return;
}

sub dump {
    my ($self, $name) = @_;
    my (undef, undef, $repos) = $self->{xd}->find_repos ('//', 1);
    my $patch = SVK::Patch->load ("$self->{xd}{svkpath}/patch/$name.svkpatch", $repos);
    warn YAML::Dump ($patch);
    return;
}

sub test {
    my ($self, $name) = @_;
    my (undef, undef, $repos) = $self->{xd}->find_repos ('//', 1);
    my $patch = SVK::Patch->load ("$self->{xd}{svkpath}/patch/$name.svkpatch", $repos);

    if (my $conflicts = $patch->applicable) {
	print loc("%*(%1,conflict) found.\n", $conflicts);
	print loc("Please do a merge to resolve conflicts and update the patch.\n");
    }

    return;
}

sub _do_update {
    my ($self, $name, $patch) = @_;

    if (my $conflicts = $patch->update (SVK::Merge->new (%$self))) {
	return loc("%*(%1,conflict) found, patch abandoned.\n", $conflicts)
    }
    $patch->store ("$self->{xd}{svkpath}/patch/$patch->{name}.svkpatch");
    return;
}

sub update {
    my ($self, $name) = @_;
    my (undef, undef, $repos) = $self->{xd}->find_repos ('//', 1);
    my $patch = SVK::Patch->load ("$self->{xd}{svkpath}/patch/$name.svkpatch", $repos);
    # XXX: check update here
    $self->_do_update ($name, $patch);
}

sub list {
    my ($self) = @_;
    my (undef, undef, $repos) = $self->{xd}->find_repos ('//', 1);
    opendir DIR, "$self->{xd}{svkpath}/patch";
    for (readdir (DIR)) {
	next if m/^\./;
	my $patch = SVK::Patch->load ("$self->{xd}{svkpath}/patch/$_", $repos);
	print "$patch->{name}\@$patch->{level}: \n";
    }
    return;
}

sub run {
    my ($self, @arg) = @_;
    my $func = $self->{cmd};
    $self->$func (@arg);
}

1;

__DATA__

=head1 NAME

SVK::Command::Patch - Manage patches

=head1 SYNOPSIS

    patch create NAME DEPOTPATH DEPOTPATH
    patch view NAME
    patch update NAME
    patch test NAME
    patch send NAME
    patch list NAME
    patch delete NAME

=head1 OPTIONS


=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
