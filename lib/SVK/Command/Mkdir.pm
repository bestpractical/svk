package SVK::Command::Mkdir;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::CommitStatusEditor;
use SVK::Command::Log;
use SVK::Util qw (get_buffer_from_editor);

sub parse_arg {
    my ($self, @arg) = @_;
    $self->usage if $#arg != 0;
    return ($self->arg_depotpath ($arg[0]));
}

sub lock { return $_[0]->lock_none }

sub do_mkdir_direct {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $edit = $self->get_commit_editor ($fs->revision_root ($fs->youngest_rev),
					 sub { print "Committed revision $_[0].\n" },
					 '/', %arg);
    # XXX: check parent, check isfile, check everything...
    $edit->open_root();
    $edit->add_directory ($arg{path});
    $edit->close_edit();

}

sub run {
    my ($self, $target) = @_;
    $self->get_commit_message ();
    $self->do_mkdir_direct ( author => $ENV{USER},
			     %$target,
			     %$self,
			   );
    return;
}

1;

=head1 NAME

mkdir - Create versioned directory.

=head1 SYNOPSIS

    mkdir DEPOTPATH

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
