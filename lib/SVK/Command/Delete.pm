package SVK::Command::Delete;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( abs2rel );

sub options {
    ($_[0]->SUPER::options,
     'K|keep-local'	=> 'keep');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;
    my $target;
    if ($#arg == 0) {
	$target = $self->arg_co_maybe ($arg[0]);
	return $target unless $target->{copath};
    }
    return $self->arg_condensed (@arg);
}

sub lock {
    my ($self, $target) = @_;
    $self->lock_target ($target);
}

sub do_delete_direct {
    my ($self, $target) = @_;
    my $m = $self->under_mirror ($target);
    if ($m && $m->{target_path} eq $target->path) {
	$m->delete;
	$target->refresh_revision;
	undef $m;
    }

    $self->get_commit_message ();
    $target->normalize;
    my ($anchor, $editor) = $self->get_dynamic_editor ($target);
    my $rev = $target->{revision};
    $rev = $m->find_remote_rev ($rev) if $m;
    $editor->delete_entry (abs2rel ($target->path, $anchor => undef, '/'), $rev, 0);
    $self->adjust_anchor ($editor);
    $self->finalize_dynamic_editor ($editor);
}

sub _ensure_mirror {
    my ($self, $target) = @_;
    my @m = $target->contains_mirror or return;
    return if !$target->{copath} && $#m == 0 && $m[0] eq $target->path;

    my $depotname = $target->depotname;
    die loc("%1 contains mirror, remove explicitly: ", "/$depotname".$target->path).
	join(',', map { "/$depotname$_" } @m)."\n"
}

sub run {
    my ($self, $target) = @_;

    $self->_ensure_mirror($target);

    if ($target->{copath}) {
	$self->{xd}->do_delete ( %$target, no_rm => $self->{keep} );
    }
    else {
	$self->do_delete_direct ( $target );
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

 -m [--message] MESSAGE	: specify commit message MESSAGE
 -F [--file] FILENAME	: read commit message from FILENAME
 -K [--keep-local]      : do not remove the local file

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
