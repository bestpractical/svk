#!/usr/bin/perl -w
use Test::More tests => 10;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('add');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
overwrite_file ("A/foo", "foobar");
overwrite_file ("A/bar", "foobar");
overwrite_file ("A/deep/baz", "foobar");
overwrite_file ("A/deep/baz~", "foobar");

is_output_like ($svk, 'add', [], qr'SYNOPSIS', 'add - help');

is_output ($svk, 'add', ['A/foo'],
	   ['A   A/', 'A   A/foo'], 'add - descendent target only');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['-q', 'A/foo'],
	   [], 'add - quiet');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ["$corpath/A/foo"],
	   ["A   $corpath/A/", "A   $corpath/A/foo"], 'add - descendent target only - abspath');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['../add/A/foo'],
	   ["A   ../add/A/", "A   ../add/A/foo"], 'add - descendent target only - relpath');
$svk->revert ('-R', '.');

TODO: {
local $TODO = 'get proper anchor';
is_output ($svk, 'add', ['A/deep/baz'],
	   ['A   A/', 'A   A/deep', 'A   A/deep/baz'],
	   'add - deep descendent target only');
}
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['A'],
	   ['A   A/', 'A   A/bar', 'A   A/foo', 'A   A/deep', 'A   A/deep/baz'],
	   'add - anchor');
$svk->revert ('-R', '.');

is_output ($svk, 'add', [qw/-N A/],
	   ['A   A/'],
	   'add - nonrecursive anchor');
is_output ($svk, 'add', ['A/foo'],
	   ['A   A/foo'],
	   'add - nonrecursive target');
$svk->revert ('-R', '.');

$svk->add (qw|-N A/foo|);
ok ($@ =~ m'do_add with targets and non-recursive not handled',
    'add - nonrecursive target only');
