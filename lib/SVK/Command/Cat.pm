package SVK::Command::Cat;
use strict;
our $VERSION = '0.14';

use base qw( SVK::Command );
use SVK::Util qw(slurp_fh);

sub options {
    ('r|revision=i'  => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;
    for (@arg) {
	my (undef, $path, undef, undef, $repos) = $self->{xd}->find_repos_from_co_maybe ($_, 1);
	my $pool = SVN::Pool->new_default;
	my $fs = $repos->fs;
	my $root = $fs->revision_root ($self->{rev} || $fs->youngest_rev);
	my $stream = $root->file_contents ($path);
	# XXX: the keyword layer interface should also have reverse
	my $layer = SVK::XD::get_keyword_layer ($root, "$path");
	my $io = new IO::Handle;
	$io->fdopen(fileno(STDOUT),"w");
	$layer->via ($io) if $layer;
	slurp_fh ($stream, $io);
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

    options:
    -r [--revision] REV:    revision

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
