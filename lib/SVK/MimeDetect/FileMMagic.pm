package SVK::MimeDetect::FileMMagic;
use strict;
use warnings;
use base qw( File::MMagic );

use SVK::Util qw( is_binary_file );

=for Workaround:

File::MMagic 1.27 doesn't correctly handle subclassing.  The object returned by
new is blessed into 'File::MMagic' instead of the subclass.  The author has
accepted a patch to correct this behavior.  Once the patched version is
released on CPAN, new() should be removed and the fixed version required.

=cut
sub new {
    my $pkg = shift;
    my $new_self = $pkg->SUPER::new(@_);
    return bless $new_self, $pkg;
}

# override the default implementation because checktype_contents is faster
sub checktype_filename {
    my ($self, $filename) = @_;

    return 'text/plain' if -z $filename;

    # read a chunk and delegate to checktype_contents()
    open my $fh, '<', $filename or die $!;
    binmode($fh);
    read $fh, my $data, 16 * 1024;
    my $type = $self->checktype_contents($data);
    return $type if $type ne 'application/octet-stream';

    # verify File::MMagic's opinion on supposedly binary data
    return $type if is_binary_file($filename);
    return 'text/plain';
}

1;

__END__

=head1 NAME

SVK::MimeDetect::FileMMagic

=head1 DESCRIPTION

Implement MIME type detection using the module File::MMagic.

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

