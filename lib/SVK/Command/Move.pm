package SVK::Command::Move;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Copy );
use SVK::Util qw ( abs2rel );
use SVK::I18N;

sub handle_direct_item {
    my $self = shift;
    $self->SUPER::handle_direct_item (@_);
    my ($editor, $anchor, $m, $src, $dst) = @_;
    $editor->delete_entry (abs2rel ($src->path, $anchor => undef, '/'),
			   $m ? $m->find_remote_rev ($src->{revision}) : $src->{revision}, 0);
    $self->adjust_anchor ($editor);
}

sub handle_co_item {
    my ($self) = shift;
    $self->{xd}->do_delete (%{$_[0]});
    $self->SUPER::handle_co_item (@_);
}

__DATA__

=head1 NAME

SVK::Command::Move - Move a file or directory

=head1 SYNOPSIS

 move DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

 -r [--revision] arg    : act on revision ARG instead of the head revision
 -m [--message] arg     : specify commit message ARG
 -C [--check-only]      : try operation but make no changes
 -P [--patch] arg       : instead of commit, save this change as a patch
 -S [--sign]            : sign this change

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Moveright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
