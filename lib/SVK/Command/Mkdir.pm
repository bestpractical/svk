package SVK::Command::Mkdir;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw ( abs2rel );

sub options {
    ($_[0]->SUPER::options,
     'p|parent' => 'parent');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg != 0;
    return ($self->arg_depotpath ($arg[0]));
}

sub lock { return $_[0]->lock_none }

sub run {
    my ($self, $target) = @_;
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

=head1 OPTIONS

 -m [--message] arg     : specify commit message ARG
 -C [--check-only]      : try operation but make no changes
 -S [--sign]            : sign this change

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
