package SVK;
use strict;
our $VERSION = '0.13';
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
    my $msg = SVK::Command->invoke ($self->{xd}, $cmd, @_);
    print $msg if $msg;
}

1;

=head1 NAME

SVK - A Distributed Version Control System

=head1 SYNOPSIS

see svk help

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
