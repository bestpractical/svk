#!/usr/bin/perl
use strict;
require 't/tree.pl';
use Test::More;
our $output;
eval "require SVN::Mirror"
or Test::More->import (skip_all => "SVN::Mirror not installed");
Test::More->import ('tests', 1);

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test();
my ($xd2, $svk2) = build_test();

$svk->mkdir ('-m', 'init', '//trunk');
my $tree = create_basic_tree ($xd, '//trunk');

my ($repospath, $path) = $xd->find_repos ('//trunk');

$svk2->mirror ('//trunk', "file://${repospath}".($path eq '/' ? '' : $path));
$svk2->sync ('//trunk');
$svk2->copy ('-m', 'local branch', '//trunk', '//local');

my ($copath, $corpath) = get_copath ('patch');
$svk2->checkout ('//local', $copath);
append_file ("$copath/B/fe", "fnord\n");
$svk2->commit ('-m', "modified on local", $copath);

$svk2->patch ('create', 'test-1', '//local', '//trunk');
$svk2->patch ('view', 'test-1');
warn $output;

ok (-e "$xd2->{svkpath}/patch/test-1.svkpatch");
mkdir ("$xd->{svkpath}/patch");
link ("$xd2->{svkpath}/patch/test-1.svkpatch", "$xd->{svkpath}/patch/test-1.svkpatch");

my ($scopath, $scorpath) = get_copath ('patch1');
$svk->checkout ('//trunk', $scopath);
overwrite_file ("$scopath/B/fe", "on trunk\nfile fe added later\n");
$svk->commit ('-m', "modified on trunk", $scopath);

$svk->patch ('view', 'test-1');
warn $output;
