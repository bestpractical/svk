#!/usr/bin/perl

require Data::Hierarchy;
require SVN::Core;
require SVN::Repos;
use strict;

sub build_test {
    my $repospath = "/tmp/svn-$$";
    my $reposbase = $repospath;
    my $repos;
    my $i = 0;
    while (-e $repospath) {
	$repospath = $reposbase . '-'. (++$i);
    }
    $repos = SVN::Repos::create("$repospath", undef, undef, undef, undef)
	or die "failed to create repository at $repospath";

    my $info = {depotmap => {'' => $repospath },
		checkout => Data::Hierarchy->new};

}

sub cleanup_test {
    my $info = shift;
    for (values %{$info->{depotmap}}) {
	die if $_ eq '/';
	diag "removing $_";
	`rm -rf $_`;
    }
}

sub tree_from_fsroot {
    # generate a hash describing a given fs root
}

sub tree_from_xdroot {
    # generate a hash describing the content in an xdroot
}

1;
