#!/usr/bin/perl -w
use Test::More tests => 10;
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
overwrite_file ("A/deep/baz", "foobar");
$svk->add('A');
is_output ($svk, 'revert', ['A/foo'],
	   [__("Reverted $corpath/A/foo")], 'revert an added file');
is_output ($svk, 'revert', ['A/foo'],
	   [__("$corpath/A/foo is not versioned; ignored.")], 'do it again');
is_output ($svk, 'revert', ['-R', 'A/deep'],
	   [__("Reverted $corpath/A/deep"),
	    __("Reverted $corpath/A/deep/bar"),
	    __("Reverted $corpath/A/deep/baz"),
	   ], 'partial revert after add');

$svk->add('A');
is_output ($svk, 'revert', ['-R'],
	   [__("Reverted $corpath/A"),
	    __("Reverted $corpath/A/deep"),
	    __("Reverted $corpath/A/deep/bar"),
	    __("Reverted $corpath/A/deep/baz"),
	    __("Reverted $corpath/A/foo"),
           ], 'revert everything');

$svk->add('A');
$svk->commit ('-m', 'commit everything');

overwrite_file ("A/foo", "foobarbaz");
overwrite_file ("A/deep/bar", "foobarbaz");
overwrite_file ("A/deep/baz", "foobarbaz");
$svk->status;

is_output ($svk, 'revert', ['-R', 'A/deep'],
	   [__("Reverted $corpath/A/deep/bar"),
	    __("Reverted $corpath/A/deep/baz"),
	   ], 'partial revert after modification');
is_output ($svk, 'revert', ['A/foo'],
	   [__("Reverted $corpath/A/foo")], 'revert a modified file');

is_output ($svk, 'revert', ['A/foo'], [], 'do it again');

append_file ("A/foo", "modified");
$svk->commit ('-m', 'modify A/foo');
overwrite_file ("A/foo", "foobarbaz");
$svk->update ('-r1');
is_output ($svk, 'st', [],
	  [__('C   A/foo')]);
is_output ($svk, 'revert', ['-R'],
	   [__("Reverted $corpath/A/foo")]);
is_output ($svk, 'st', [], []);
