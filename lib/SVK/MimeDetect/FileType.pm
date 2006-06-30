package SVK::MimeDetect::FileType;
use strict;
use warnings;
use base qw( File::Type );

use SVK::Util qw( is_binary_file );

sub checktype_filename {
    my ($self, $filename) = @_;

    return 'text/plain' if -z $filename;

    open my $fh, '<', $filename or die $!;
    binmode($fh);
    read $fh, my $data, 16*1024 or return undef;

    my $type = File::Type->checktype_contents($data);
    return $type if $type ne 'application/octet-stream';

    # verify File::Type's opinion on supposedly binary data
    return 'application/octet-stream' if is_binary_file($filename);
    return 'text/plain';
}

1;

__END__

=head1 NAME

SVK::MimeDetect::FileType

=head1 DESCRIPTION

Use L<File::Type> for automatic MIME type detection.

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

