package SVK::Command::Mkdir;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( abs2rel get_anchor make_path );

sub options {
    ($_[0]->SUPER::options,
     'p|parent' => 'parent');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return map { $self->{xd}->target_from_copath_maybe($_) } @arg;
}

sub lock {
    my $self = shift;
    $self->lock_coroot(@_);
}

sub ensure_parent {
    my ($self, $target) = @_;
    my $dst = $target->new;
    $dst->anchorify;
    die loc("Path %1 is not a checkout path.\n", $dst->{report})
	unless defined $dst->{copath};
    unless (-e $dst->{copath}) {
	die loc ("Parent directory %1 doesn't exist, use -p.\n", $dst->{report})
	    unless $self->{parent};
	# this sucks
	my ($added_root) = make_path($dst->{report});
	my $add = $self->command('add', { recursive => 1 });
	$add->run($add->parse_arg($added_root));
    }
    unless (-d $dst->{copath}) {
	die loc ("%1 is not a directory.\n", $dst->{report});
    }
    unless ($dst->root($self->{xd})->check_path ($dst->{path})) {
	my $info = $self->{xd}{checkout}->get($dst->{copath});
	die loc ("Parent directory %1 is unknown, add first.\n", $dst->{report})
	    unless $info->{'.schedule'};
    }
}

sub run {
    my ($self, @target) = @_;

    # XXX: better check for @target being the same type
    if (grep {$_->{copath}} @target) {
	$self->ensure_parent($_) for @target;
	for (@target) {
	    make_path($_->{report});
	}
	for (@target) {
	    my $add = $self->command('add');
	    $add->run($add->parse_arg($_->{report}));
	}
	return ;
    }

    die loc("Mkdir for more than one depotpath is not supported yet.\n")
	if scalar @target > 1;

    my ($target) = @target;
    $self->get_commit_message ();
    my ($anchor, $editor) = $self->get_dynamic_editor ($target);
    $editor->close_directory
	($editor->add_directory (abs2rel ($target->path, $anchor => undef, '/'),
				 0, undef, -1));
    $self->adjust_anchor ($editor);
    $self->finalize_dynamic_editor ($editor);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Mkdir - Create a versioned directory

=head1 SYNOPSIS

 mkdir DEPOTPATH
 mkdir PATH...

=head1 OPTIONS

 -p [--parent]          : create intermediate directories as required
 -m [--message] MESSAGE : specify commit message MESSAGE
 -F [--file] FILENAME   : read commit message from FILENAME
 --template             : use the specified message as the template to edit
 --encoding ENC         : treat -m/-F value as being in charset encoding ENC
 -P [--patch] NAME      : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -C [--check-only]      : try operation but make no changes
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
