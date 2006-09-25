package SVK::Editor::TxnCleanup;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
use base 'SVK::Editor::ByPass';


=head1 NAME

SVK::Editor::TxnCleanup - An editor that aborts a txn when it is aborted

=head1 SYNOPSIS

 my $editor = ...
 # stack the txn cleanup editor on
 $editor = SVK::Editor::TxnCleanup-> (_editor => [$editor], txn => $txn );
 # ... do some stuff ...
 $editor->abort_edit;
 # $txn->abort gets called.

=cut

sub abort_edit {
    my $self = shift;
    my $ret = $self->SUPER::abort_edit(@_);
    $self->{txn}->abort;
    delete $self->{txn};
    return $ret;
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
