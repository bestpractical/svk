package SVK::Command::Proplist;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;

sub options {
    ('v|verbose'    => 'verbose',
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_co_maybe ($_)} @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	$target->depotpath ($self->{rev})
	    if defined $self->{rev};
	my $props = $self->{xd}->do_proplist ( $target );
	return unless %$props;
	print loc("Properties on %1:\n", $target->{report} || '.');
	for my $key (sort keys %$props) {
	    my $value = $props->{$key};
	    print $self->{verbose} ? "  $key: $value\n" : "  $key\n";
	}
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Proplist - List all properties on files or dirs

=head1 SYNOPSIS

 proplist PATH...

=head1 OPTIONS

 -r [--revision] rev:    revision
 -v [--verbose]:         print extra information

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
