#!/usr/bin/perl -w

use strict;
BEGIN { require 't/tree.pl' };
plan_svm tests => 12;

our ($output, $answer);
my ($xd, $svk) = build_test();

$svk->mkdir ('-m', 'init', '//foo');
my $tree = create_basic_tree ($xd, '//foo');

waste_rev ($svk, '//waste') for (1..100);

$svk->cp (-m => 'bar', '//foo' => '//bar');
$svk->cp (-m => 'baz', '//bar/B' => '//baz');

is_ancestor ($svk, '//bar',
	     '/foo', 3);
is_ancestor ($svk, '//bar/B/S/P',
	     '/foo/B/S/P', 3,
	     '/foo/A/P', 2);
is_ancestor ($svk, '//bar/B/S/P/pe',
	     '/foo/B/S/P/pe', 3,
	     '/foo/A/P/pe', 2);
is_ancestor ($svk, '//bar/A',
	     '/foo/A', 3);
is_ancestor ($svk, '//baz',
	     '/bar/B', 204,
	     '/foo/B', 3);
is_ancestor ($svk, '//baz/S',
	     '/bar/B/S', 204,
	     '/foo/B/S', 3,
	     '/foo/A', 2);
$svk->mkdir (-m => 'fnord', '//baz/fnord');
$svk->cp (-m => 'xyz', '//baz' => '//xyz');
is_ancestor ($svk, '//xyz/fnord',
	     '/baz/fnord', 206);
my ($repospath, $path, $repos) = $xd->find_repos ('//', 1);
my $fs = $repos->fs;

#my $target = SVK::Target->new (repos => $repos, path => '/baz/S');
#$target->copy_ancestors;

$svk->ps(-m=>'mod', 'foo', 'bar', '//baz/S');
is_deeply ([SVK::Target::nearest_copy ($fs->revision_root (208), '/baz/S')],
	   [205, 204, '/bar/B/S']);
is_deeply ([SVK::Target::nearest_copy ($fs->revision_root (208), '/baz')],
	   [205, 204, '/bar/B']);
is_deeply ([SVK::Target::nearest_copy ($fs->revision_root (204), '/bar/B/S')],
	   [204, 3, '/foo/B/S']);
is_deeply ([SVK::Target::nearest_copy ($fs->revision_root (3), '/foo/B/S')],
	   [3, 2, '/foo/A']);
is_deeply ([SVK::Target::nearest_copy ($fs->revision_root (2), '/foo/A')],
	   []);
