package SVK::Log::Filter::Output;

use base qw( SVK::Log::Filter );

1;

__END__

=head1 NAME

SVK::Log::Filter::Output - base class for output log filters

=head1 DESCRIPTION

All log filters which are intended to display log messages should extend this
base class.  For more details about writing log filters, see
L<SVK::Log::Filter>.

=head1 AUTHORS

Michael Hendricks <michael@ndrix.org>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
