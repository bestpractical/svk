package SVK::Command::Annotate;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use Algorithm::Annotate;

sub options {
    ('x|cross'  => 'cross');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    return $self->arg_co_maybe (@arg);
}

sub run {
    my ($self, $target) = @_;

    my $pool = SVN::Pool->new_default_sub;
    my $fs = $target->{repos}->fs;
    my $root = $fs->revision_root ($target->{revision});
    my $ann = Algorithm::Annotate->new;
    my @revs;

    my $hist = $root->node_history ($target->{path});
    my $spool = SVN::Pool->new_default ($pool);
    $self->{cross} ||= 0;
    while ($hist = $hist->prev($self->{cross})) {
	my ($path, $rev) = $hist->location;
	unshift @revs, [$path, $rev];
	$spool->clear;
    }

    print loc("Annotations for %1 (%2 active revisions):\n", $target->{path}, scalar @revs);
    print '*' x 16;
    print "\n";
    for (@revs) {
	$spool->clear;
	local $/;
	my ($path, $rev) = @$_;
	my $content = $fs->revision_root ($rev)->file_contents ($path);
	$content = [split "[\n\r]", <$content>];
	no warnings 'uninitialized';
	$ann->add ( sprintf("%6s\t(%8s %10s):\t\t", $rev,
			    $fs->revision_prop ($rev, 'svn:author'),
			    substr($fs->revision_prop ($rev, 'svn:date'),0,10)),
		    $content);
    }

    my $final;
    if ($target->{copath}) {
	$final = SVK::XD::get_fh ($target->root ($self->{xd}), '<', $target->{path}, $target->{copath});
	$ann->add ( "\t(working copy): \t\t", [map {chomp;$_}<$final>]);
	seek $final, 0, 0;
    }
    else {
	$final = $fs->revision_root($revs[-1][1])->file_contents($revs[-1][0]);
    }
    my $result = $ann->result;
    while (my $info = shift @$result) {
	print $info.<$final>;
    }

}

1;

__DATA__

=head1 NAME

SVK::Command::Annotate - Print files with per-line revision and author info

=head1 SYNOPSIS

 annotate FILE

=head1 OPTIONS

 -x [--cross]:      trace cross copied revisions

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
