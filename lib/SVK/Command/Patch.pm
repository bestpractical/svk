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

my %cmd = map {$_ => 1} qw/view dump update regen update test send delete/;
$cmd{create} = $cmd{list} = 0;

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

sub create {
    my ($self, $name, @arg) = @_;
    my $fname = "$self->{xd}{svkpath}/patch";
    mkdir ($fname);
    $fname .= "/$name.svkpatch";
    return "file $fname already exists, use $0 patch regen or update $name instead\n"
	if -e $fname;

    my ($src, $dst) = map {$self->arg_depotpath ($_) } @arg;
    die loc("repos paths mismatch") unless $src->same_repos ($dst);

    my $patch = SVK::Patch->new ($name, $self->{xd}, $self->{xd}->find_depotname ($arg[0]),
				 $src, $dst);
    my $ret = $self->regen ($patch);
    unless ($ret) {
	print loc ("Patch $name created.\n");
    }
    return $ret;
}

sub view {
    my ($self, $patch) = @_;
    $patch->view;
    return;
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

sub list {
    my ($self) = @_;
    my (undef, undef, $repos) = $self->{xd}->find_repos ('//', 1);
    opendir DIR, "$self->{xd}{svkpath}/patch";
    for (readdir (DIR)) {
	next if m/^\./;
	s/\.svkpatch$//;
	my $patch = $self->_load ($_);
	print "$patch->{name}\@$patch->{level}: \n";
    }
    return;
}

sub _store {
    my ($self, $patch) = @_;
    $patch->store ("$self->{xd}{svkpath}/patch/$patch->{name}.svkpatch");
}

sub _load {
    my ($self, $name) = @_;
    # XXX: support alternative path
    SVK::Patch->load ("$self->{xd}{svkpath}/patch/$name.svkpatch",
		      $self->{xd}, $self->{depot} || '');
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

 patch create NAME DEPOTPATH DEPOTPATH
 patch list
 patch view NAME
 patch regen NAME
 patch update NAME
 patch apply NAME
 patch send NAME
 patch delete NAME

=head1 OPTIONS

 None

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
