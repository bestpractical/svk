package SVK::Command::Annotate;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( traverse_history );
use Algorithm::Annotate;

sub options {
    ('x|cross'  => 'cross',
     'r|revision=i'  => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    return $self->arg_co_maybe (@arg);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $target) = @_;

    $target->as_depotpath ($self->{rev}) if defined $self->{rev};
    my $fs = $target->{repos}->fs;
    my $ann = Algorithm::Annotate->new;
    my @revs;

    traverse_history (
        root     => $fs->revision_root ($target->{revision}),
        path     => $target->{path},
        cross    => $self->{cross},
        callback => sub {
            my ($path, $rev) = @_;
            unshift @revs, [ $path, $rev ];
            1;
        }
    );

    print loc("Annotations for %1 (%2 active revisions):\n", $target->{path}, scalar @revs);
    print '*' x 16;
    print "\n";
    for (@revs) {
	local $/;
	my ($path, $rev) = @$_;
	my $content = $fs->revision_root ($rev)->file_contents ($path);
	$content = [split /\015?\012|\015/, <$content>];
	no warnings 'uninitialized';
	$ann->add ( sprintf("%6s\t(%8s %10s):\t\t", $rev,
			    $fs->revision_prop ($rev, 'svn:author'),
			    substr($fs->revision_prop ($rev, 'svn:date'),0,10)),
		    $content);
    }

    my $final;
    if ($target->{copath}) {
	$final = SVK::XD::get_fh ($target->root ($self->{xd}), '<', $target->{path}, $target->{copath});
	local $/;
	$final = [split /\015?\012|\015/, <$final>];
	$ann->add ( "\t(working copy): \t\t", $final );
    }
    else {
	local $/;
	$final = $fs->revision_root($revs[-1][1])->file_contents($revs[-1][0]);
	$final = [split /\015?\012|\015/, <$final>];
    }

    my $result = $ann->result;
    while (my $info = shift @$result) {
	print $info, shift(@$final), "\n";
    }

}

1;

__DATA__

=head1 NAME

SVK::Command::Annotate - Display per-line revision and author info

=head1 SYNOPSIS

 annotate FILE
 annotate DEPOTPATH[@rev]

=head1 OPTIONS

 -x [--cross]           : track revisions copied from elsewhere

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
