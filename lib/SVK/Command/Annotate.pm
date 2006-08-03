package SVK::Command::Annotate;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( traverse_history HAS_SVN_MIRROR );
use Algorithm::Annotate;

sub options {
    ('x|cross'       => 'cross',
     'remoterev'     => 'remoterev',
     'r|revision=s'  => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    return $self->arg_co_maybe (@arg);
}

sub run {
    my ($self, $target) = @_;
    my $m = $target->is_mirrored;
    my $fs = $target->repos->fs;
    my $ann = Algorithm::Annotate->new;
    my @paths;

    $target = $self->apply_revision($target) if $self->{rev};

    traverse_history (
        root     => $target->as_depotpath->root,
        path     => $target->path,
        cross    => $self->{cross},
        callback => sub {
            my ($path, $rev) = @_;
            unshift @paths,
		$target->as_depotpath($rev)->new(path => $path);
            1;
        }
    );

    print loc("Annotations for %1 (%2 active revisions):\n", $target->path, scalar @paths);
    print '*' x 16;
    print "\n";
    for my $t (@paths) {
	local $/;
	my $content = $t->root->file_contents($t->path);
	$content = [split /\015?\012|\015/, <$content>];
	no warnings 'uninitialized';
	my $rrev = ($m && $self->{remoterev}) ? $m->find_remote_rev($t->revision) : $t->revision;
	$ann->add ( sprintf("%6s\t(%8s %10s):\t\t", $rrev,
			    $fs->revision_prop($t->revision, 'svn:author'),
			    substr($fs->revision_prop ($t->revision, 'svn:date'),0,10)),
		    $content);
    }

    # TODO: traverse history should just DTRT and we dont need to special case here
    my $last = $target->isa('SVK::Path::Checkout')
	? $target : $paths[-1];
    my $final;
    {
	local $/;
	$final = $last->root->file_contents($last->path);
	$final = [split /\015?\012|\015/, <$final>];
	$ann->add ( "\t(working copy): \t\t", $final )
	    if $target->isa('SVK::Path::Checkout');
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

 annotate [PATH][@REV]
 annotate [-r REV] [PATH]
 annotate DEPOTPATH[@REV]
 annotate [-r REV] DEPOTPATH

=head1 OPTIONS

 -r [--revision] REV    : annotate up to revision
 -x [--cross]           : track revisions copied from elsewhere
 --remoterev            : display remote revision numbers (on mirrors only)

=head1 NOTES

Note that -r REV file will do annotation up to REV,
while file@REV will do annotation up to REV,
plus the checkout copy differences.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
