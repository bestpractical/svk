package SVK::MimeDetect;
use strict;
use warnings;
use SVK::I18N;

# die if this method is not overriden
sub new {
    my ($self) = @_;
    my $pkg = ref $self || $self;
    die loc(
        "%1 needs to implement new().\n" .
        "Read the documentation of SVK::MimeDetect for details\n",
        $pkg
    );
}

# die if this method is not overriden
sub checktype_filename {
    my ($self) = @_;
    my $pkg = ref $self || $self;
    die loc(
        "%1 needs to implement checktype_filename().\n" .
        "Read the documentation of SVK::MimeDetect for details\n",
        $pkg
    );
}

1;

__END__

=head1 NAME

SVK::MimeDetect - interface for MIME type detection algorithms

=head1 DESCRIPTION

This defines an interface for MIME type detection algorithms.  A MIME type
detection module doesn't need to inherit from this module, but it does need to
provide the same interface.  See L</INTERFACE> for details.

=head1 INTERFACE

=head2 new

C<new> should return a new object which implements the L</checktype_filename>
method described below.  The default implementation simply returns an empty,
blessed hash.

=head2 checktype_filename

Given a single, absolute filename as an argument, this method should return a
scalar with the MIME type of the file or C<undef> if there is an error.

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

