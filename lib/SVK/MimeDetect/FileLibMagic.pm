package SVK::MimeDetect::FileLibMagic;
use strict;
use warnings;

use File::LibMagic 0.84 qw( :complete );
use SVK::Util      qw( is_binary_file );

sub new {
    my ($pkg) = @_;

    my $handle = magic_open(MAGIC_MIME);
    magic_load( $handle, "" );    # default magic file

    return bless \$handle, $pkg;
}

sub checktype_filename {
    my ($self, $filename) = @_;

    return 'text/plain' if -z $filename;

    my $type = magic_file( $$self, $filename );
    $type =~ s{ \s* ; \s* charset= .* \z}{}xmsg;    # strip charset info
    return $type if $type ne 'application/octet-stream';

    # verify File::LibMagic's opinion on supposedly binary data
    return 'application/octet-stream' if is_binary_file($filename);
    return 'text/plain';
}

sub DESTROY {
    my ($self) = @_;
    magic_close($$self);
}

1;

__END__

=head1 NAME

SVK::MimeDetect::FileLibMagic

=head1 DESCRIPTION

Implement MIME type detection using the module File::LibMagic

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

