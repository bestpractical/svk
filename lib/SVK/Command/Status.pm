package SVK::Command::Status;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::Editor::Status;

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return $self->arg_condensed (@arg);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target) = @_;
    my $xdroot = $self->{xd}->xdroot (%$target);
    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $xdroot,
	  nodelay => 1,
	  delete_verbose => 1,
	  editor => SVK::Editor::Status->new (report => $target->{report}),
	  cb_conflict => \&SVK::Editor::Status::conflict,
	  cb_unknown =>
	  sub { $_[1] =~ s|^\Q$target->{copath}\E/|$target->{report}|;
		print "?   $_[1]\n" }
	);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Status - Display the status of items in the checkout copy

=head1 SYNOPSIS

    status [PATH..]

=head1 OPTIONS


=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
