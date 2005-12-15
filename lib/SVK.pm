package SVK;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

# Load classes on demand.
use Class::Autouse qw(SVK::Command);

use SVN::Core;
BEGIN {
    # autouse hates Devel::DProf. If we're running with DProf,
    # we need to emasculate autouse by blowing a new import sub into its
    # package at runtime.
    if($main::INC{'Devel/DProf.pm'})  {
	no strict 'refs';
	$main::INC{'autouse.pm'} = __FILE__;
	*{'autouse::import'} = sub {
	    require UNIVERSAL::require;
	    shift; # get rid of $CLASS
	    my $class = shift;
	    $class->require or die $!;
	    $class->export_to_level(1, undef, @_);
        }
    }
}

sub import {
    return unless ref ($_[0]);
    our $AUTOLOAD = 'import';
    goto &AUTOLOAD;
}

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}

sub AUTOLOAD {
    my $cmd = our $AUTOLOAD;
    $cmd =~ s/^SVK:://;
    return if $cmd =~ /^[A-Z]+$/;

    no strict 'refs';
    no warnings 'redefine';
    *$cmd = sub {
        my $self = shift;
        my ($buf, $output, $ret) = ('');
        open $output, '>', \$buf if $self->{output};
        eval { $ret = SVK::Command->invoke ($self->{xd}, $cmd, $output, @_) };
        if ($output) {
            close $output;
            ${$self->{output}} = $buf;
        }
        return $ret;
    };
    goto &$cmd;
}

1;

__DATA__

=head1 NAME

SVK - A Distributed Version Control System

=head1 SYNOPSIS

  use SVK;
  use SVK::XD;
  $xd = SVK::XD->new (depotmap => { '' => '/path/to/repos'});

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

=back

=head1 METHODS

All methods are autoloaded and deferred to
C<SVK::Command-E<gt>invoke>.

=head1 SEE ALSO

L<svk>, L<SVK::XD>, L<SVK::Command>.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
