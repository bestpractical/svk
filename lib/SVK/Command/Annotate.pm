package SVK::Command::Annotate;
use strict;
our $VERSION = '0.13';
use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use Algorithm::Annotate;

sub options {
    ('x|cross'  => 'cross');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_co_maybe (@arg);
}

sub run {
    my ($self, $target) = @_;

    my $fs = $target->{repos}->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);
    my $ann = Algorithm::Annotate->new;
    my @revs;

    my $pool = SVN::Pool->new_default_sub;
    my $hist = $root->node_history ($target->{path});
    $self->{cross} ||= 0;
    while ($hist = $hist->prev($self->{cross})) {
	$pool->clear;
	my ($path, $rev) = $hist->location;
	unshift @revs, $rev;
    }

    print loc("Annotations for %1 (%2 active revisions):\n", $target->{path}, scalar @revs);
    print '*' x 16;
    print "\n";
    for (@revs) {
	$pool->clear;
	local $/;
	my $content = $fs->revision_root($_)->file_contents($target->{path});
	$content = [split "[\n\r]", <$content>];
	$ann->add ( sprintf("%6s\t(%8s %10s):\t\t", $_,
			    $fs->revision_prop ($_, 'svn:author') || '',
			    substr($fs->revision_prop ($_, 'svn:date'),0,10)),
		    $content);
    }

    my $final;
    if ($target->{copath}) {
	open $final, $target->{copath};
	$ann->add ( "\t(working copy): \t\t", [map {chomp;$_}<$final>]);
	seek $final, 0, 0;
    }
    else {
	$final = $fs->revision_root($revs[-1])->file_contents($target->{path});
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
