package SVK;
use strict;
our $VERSION = '0.19';
use SVK::Command;
our $AUTOLOAD;

sub import {
    return unless ref ($_[0]);
    $AUTOLOAD = 'import';
    goto &AUTOLOAD;
}

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}

sub AUTOLOAD {
    my $self = shift;
    my $cmd = $AUTOLOAD;
    $cmd =~ s/^SVK:://;
    return if $cmd =~ /^[A-Z]+$/;
    my ($buf, $output) = ('');
    open $output, '>', \$buf if $self->{output};
    eval { SVK::Command->invoke ($self->{xd}, $cmd, $output, @_) };
    if ($output) {
	close $output;
	${$self->{output}} = $buf;
    }
}

1;

__DATA__

=head1 NAME

SVK - A Distributed Version Control System

=head1 SYNOPSIS

  use SVK;
  use XD;

  $xd = SVK::XD->new
      (depotmap => { '' => '/path/to/repos'},
       checkout => Data::Hierarchy->new);

  $svk = SVK->new (xd => $xd, output => \$output);
  # serialize the $xd object for future use.

  $svk->ls ('//'); # check $output for its output
  ...

=head1 DESCRIPTION

C<SVK> is the class that loads L<SVK::Command> and invokes them. You can
use it in your program to do what you do with the L<svk> command line
interface.

=head1 CONSTRUCTOR

Options to C<new>:

=over

=item xd

L<SVK::XD> object that handles depot and checkout copy mapping.

=item output

A scalar reference. After command invocation the output will be stored
in the scalar. By default the output is not held in any scalar and
will be printed to STDOUT.

=head1 METHODS

All methods are autoloaded and deferred to
C<SVK::Command-E<gt>invoke>.

=back

=head1 SEE ALSO

L<svk>, L<SVK::XD>, L<SVK::Command>.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
