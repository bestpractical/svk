#!/usr/bin/perl -w
use Test::More tests => 9;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('delete');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);

is_output_like ($svk, 'delete', [], qr'SYNOPSIS', 'delete - help');

chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
overwrite_file ("A/foo", "foobar");
overwrite_file ("A/bar", "foobar");
overwrite_file ("A/deep/baz", "foobar");

$svk->add ('A');
$svk->commit ('-m', 'init');

is_output ($svk, 'delete', ['A/foo'],
	   ['D   A/foo'], 'delete - file');
ok (!-e 'A/foo', 'delete - copath deleted');
is_output ($svk, 'status', [],
	   ['D   A/foo'], 'delete - status');

$svk->revert ('-R', '.');

is_output ($svk, 'delete', ['--keep-local', 'A/foo'],
	   ['D   A/foo'], '');
ok (-e 'A/foo', 'copath not deleted');
is_output ($svk, 'status', [],
	   ['D   A/foo'], 'copath not deleted');


is_output ($svk, 'delete', ["$corpath/A/foo"],
	   ["D   $corpath/A/foo"], 'delete - file - abspath');
$svk->revert ('-R', '.');

is_output ($svk, 'delete', ['-m', 'rm directly', '//A/deep'],
	  ['Committed revision 2.'], 'rm directly');

# XXX: more checkout tests

