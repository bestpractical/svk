package SVK::Command::Cat;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::Util qw(slurp_fh);

sub options {
    ('r|revision=i'  => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return map { $self->arg_co_maybe ($_) } @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;
    my $pool = SVN::Pool->new_default;
    for my $target (@arg) {
	$pool->clear;
	$target->as_depotpath ($self->{rev});
	my $root = $target->root ($self->{xd});
	my $stream = $root->file_contents ($target->{path});
	# XXX: the keyword layer interface should also have reverse
	my $layer = SVK::XD::get_keyword_layer ($root, $target->{path},
						$root->node_proplist ($target->{path}));
	no strict 'refs';
	my $io = \*{select()};
	$layer->via ($io) if $layer;
	slurp_fh ($stream, $io);
	binmode $io;
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Cat - Output the file from depot

=head1 SYNOPSIS

 cat [DEPOTPATH|PATH...]

=head1 OPTIONS

 -r [--revision] arg    : act on revision ARG instead of the head revision

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
