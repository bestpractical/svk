package SVK::Editor::Translate;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);


=head1 NAME

SVK::Editor::Translate - An editor that translates path names

=head1 SYNOPSIS

 my $editor = ...
 # stack the translate editor on
 $editor = SVK::Editor::Translated-> (_editor => [$editor], translate => sub {$_[0]})

=cut

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = our $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;

    $self->{translate}->($arg[0])
	if SVK::Editor::Patch->baton_at ($func) == 1;
    $func = "SUPER::$func";
    $self->$func (@arg);
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
