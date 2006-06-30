package SVK::MimeDetect::Internal;
use strict;
use warnings;

use SVK::Util qw( is_binary_file );

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub checktype_filename {
    my ($self, $filename) = @_;
    return 'application/octet-stream' if is_binary_file($filename);
    return 'text/plain';
}

1;

__END__

=head1 NAME

SVK::MimeDetect::Internal - minimalist MIME type detection

=head1 DESCRIPTION

This class performs the least amount of MIME type detection possible while
still providing enough metadata for SVK to function properly.  It simply
assigns 'application/octet-stream' to any file that looks like binary data.  It
assigns 'text/plain' to everything else.

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

