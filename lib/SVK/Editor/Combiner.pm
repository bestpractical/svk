package SVK::Editor::Combiner;
use strict;

use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
use base 'SVK::Editor::ByPass';

=head1 NAME

SVK::Editor::Combiner - An editor combining several editor calls to one

=head1 SYNOPSIS


=cut

sub replay {
    my ($self, $editor, $base_rev) = @_;
}

sub close_edit {
    my ($self) = @_;
    $self->abort_edit;
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
