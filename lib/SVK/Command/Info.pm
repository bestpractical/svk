package SVK::Command::Info;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Merge );
use SVK::XD;
use SVK::Merge;
use SVK::I18N;
use SVK::Util qw (find_svm_source resolve_svm_source);

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_co_maybe ($_)} @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	my ($copath,$path,$repos,$depotpath) = @$target{qw/copath path repos depotpath/};
	my $yrev = $repos->fs->youngest_rev;
	my $rev = $target->{cinfo}{revision}||$yrev;
	my (undef,$m) = resolve_svm_source($repos, find_svm_source($repos,$path));
	$self->{merge} = SVK::Merge->new (%$self);
	my %ancestors = $self->{merge}->copy_ancestors($repos,$path,$yrev, 1);
	my $minfo = $self->{merge}->find_merge_sources($repos,$path,$yrev, 0,1);
	print loc("Checkout Path: %1\n",$copath) if($copath);
	print loc("Depot Path: %1\n", $depotpath);
	print loc("Revision: %1\n", $rev);
	print loc(
	    "Last Changed Rev.: %1\n",
	    $repos->fs->revision_root($rev)->node_created_rev($path)
	);
	print loc("Mirrored From: %1, Rev. %2\n",$m->{source},$m->{fromrev})
	    if($m->{source});
	for (keys %ancestors) {
	    print loc("Copied from %1, Rev. %2\n",(split/:/)[1],$ancestors{$_});
	}
	for (keys %$minfo) {
	    print loc("Merge from %1, Rev. %2\n",(split/:/)[1],$minfo->{$_});
	}
	print "\n";
    }
}

1;

__DATA__

=head1 NAME

SVK::Command::Info - Display information about a file or directory

=head1 SYNOPSIS

    info [PATH | DEPOTPATH]

=head1 OPTIONS

   None

=head1 DESCRIPTIONS

For example, here's the way to display the info of a checkout path

 % svk info ~/dev/svk
 Checkout Path: /Users/gugod/dev/svk
 Depot Path: //svk/local
 Revision: 447
 Last Changed Rev.: 447
 Copied from /svk/trunk, Rev. 434
 Merge from /svk/trunk, Rev. 445

You can see the result has some very basic information,
the actual depot path, and current revision. Below are advanced
information about the copy/merge log about this B<depot path>.
The result of 'svk info //svk/local' is almost the same as above,
except for the 'Checkout Path:' line is not there, because
you're not refering to a checkout path.

One thing you have to notice is the revision number on 'Copied from'
and 'Merge from' line is not the one to //svk/local after
copy/merge, but is to //svk/trunk. The example above state that,
"//svk/local is copied from the 434-th revision of //svk/trunk", and
"//svk/local is merge from the 445-th revision of //svk/trunk".
So if you do a 'svk log -r 434 //svk/local', svk would tell you
that //svk/local doesn't exist at revision 434.

So far there is no easy way to tell the actual revision number
of //svk/local right after the copy/merge.

If the target depot path, or the corresponding depot path of the
target checkout path is actually a mirroring path, it would display
like this:

 % svk info //svk/trunk
 Depot Path: //svk/trunk
 Revision: 447
 Last Changed Rev.: 445
 Mirrored From: https://svn.elixus.org/repos/member/clkao/svk, Rev. 1744

So you can see this depot path is mirror from a remote repository,
and so far mirrored up to revision 1774.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
