#!/usr/bin/perl
use Test::More tests => 4;
use strict;
use File::Path;
require 't/tree.pl';

my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('import');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
mkdir $copath;
overwrite_file ("$copath/filea", "foobarbazz");
overwrite_file ("$copath/fileb", "foobarbazz");
overwrite_file ("$copath/filec", "foobarbazz");
mkdir "$copath/dir";
overwrite_file ("$copath/dir/filed", "foobarbazz");

$svk->import ('-m', 'test import', '//import', $copath);

overwrite_file ("$copath/filea", "foobarbazzblah");
overwrite_file ("$copath/dir/filed", "foobarbazzbozo");

unlink "$copath/fileb";

$svk->import ('-m', 'test import', '//import', $copath);
rmtree [$copath];
$svk->checkout ('//import', $copath);

ok (-e "$copath/filea");
ok (!-e "$copath/fileb");
ok (-e "$copath/filec");
ok (-e "$copath/dir/filed");
