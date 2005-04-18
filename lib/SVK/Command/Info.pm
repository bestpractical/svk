package SVK::Command::Info;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Merge );
use SVK::XD;
use SVK::Merge;
use SVK::I18N;
use SVK::Util qw (find_svm_source resolve_svm_source);
use YAML;

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_co_maybe ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;
    my $exception='';
    for my $target (@arg) {
	my ($copath,$path,$repos,$depotpath) = @$target{qw/copath path repos depotpath/};
	my $yrev = $repos->fs->youngest_rev;
	my $rev = $target->{copath} ?
	    $self->{xd}{checkout}->get ($target->{copath})->{revision} : $yrev;

	$target->{revision} = $rev;
	my (undef,$m) = eval'resolve_svm_source($repos, find_svm_source($repos,$path,$rev))';
        if($@) { print "$@\n"; $exception .= "$@\n" ; next }
	print loc("Checkout Path: %1\n",$copath) if($copath);
	print loc("Depot Path: %1\n", $depotpath);
	print loc("Revision: %1\n", $rev);
	print loc(
	    "Last Changed Rev.: %1\n",
	    $repos->fs->revision_root($rev)->node_created_rev($path)
	);
	print loc("Mirrored From: %1, Rev. %2\n",$m->{source},$m->{fromrev})
	    if($m->{source});
	for ($target->copy_ancestors) {
	    print loc("Copied From: %1, Rev. %2\n", $_->[0], $_->[1]);
	}
	$self->{merge} = SVK::Merge->new (%$self);
	my $minfo = $self->{merge}->find_merge_sources ($target, 0,1);
	for (keys %$minfo) {
	    print loc("Merged From: %1, Rev. %2\n",(split/:/)[1],$minfo->{$_});
	}
	print "\n";
    }
    die($exception) if($exception);
}

1;

__DATA__

=head1 NAME

SVK::Command::Info - Display information about a file or directory

=head1 SYNOPSIS

 info [PATH | DEPOTPATH]

=head1 OPTIONS

 None

=head1 DESCRIPTION

For example, here's the way to display the info of a checkout path:

 % svk info ~/dev/svk
 Checkout Path: /Users/gugod/dev/svk
 Depot Path: //svk/local
 Revision: 447
 Last Changed Rev.: 447
 Copied From: /svk/trunk, Rev. 434
 Merge From: /svk/trunk, Rev. 445

You can see the result has some basic information: the actual depot path,
and current revision. Next are advanced information about copy and merge
source for this depot path.

The result of C<svk info //svk/local> is almost the same as above,
except for the C<Checkout Path:> line is not there, because
you are not referring to a checkout path.

Note that the revision numbers on C<Copied From:> and C<Merge From:> lines
are for the source path (//svk/trunk), not the target path (//svk/local).
The example above state that, I<//svk/local is copied from the revision 434
of //svk/trunk>, and I<//svk/local was merged from the revision 445 of
//svk/trunk>.  Hence if you do a C<svk log -r 434 //svk/local>, svk would tell
you that //svk/local does not exist at revision 434.

So far there is no easy way to tell the actual revision number
of //svk/local right after a copy or merge.

If the target is a depot path, or the corresponding depot path of the target
checkout path is actually a mirroring path, the output of this command will
look like this:

 % svk info //svk/trunk
 Depot Path: //svk/trunk
 Revision: 447
 Last Changed Rev.: 445
 Mirrored From: svn://svn.clkao.org/svk, Rev. 1744

So you can see this depot path is mirror from a remote repository,
and so far mirrored up to revision 1774.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
