#!/usr/bin/perl -w
use Test::More tests => 4;
use strict;
BEGIN { require 't/tree.pl' };
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('revert');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
overwrite_file ("A/foo", "foobar");
overwrite_file ("A/deep/bar", "foobar");
$svk->add('A');
$svk->commit('-m', 'commit everything');
#remove the contents
overwrite_file ("A/deep/bar", "fooishbar");
$svk->remove('A/deep/bar');
#remove the folder
$svk->remove('A/deep');
ok(!-d "$copath/A/deep",'A/deep should be gone now');

#changed my mind
$svk->revert('A/deep');
ok(-d "$corpath/A/deep",'revert should bring A/deep back');
$svk->revert('A/deep/bar');
ok(-f "$corpath/A/deep/bar",'revert should bring A/deep/bar back');
is_file_content("$corpath/A/deep/bar","foobar", 'revert should restore the contents of A/deep/bar');
