#!/usr/bin/perl -w
use Test::More tests => 11;
use strict;
BEGIN { require 't/tree.pl' };
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('status');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
overwrite_file ("A/foo", "foobar");
overwrite_file ("A/foo~", "foobar");
overwrite_file ("A/bar", "foobar");
overwrite_file ("A/deep/baz", "foobar");

is_output_like ($svk, 'status', ['--help'], qr'SYNOPSIS');

is_output ($svk, 'status', [],
	   ['?   A'], 'status - unknwon');
$svk->add ('-N', 'A');
$svk->add ('A/foo');
is_output ($svk, 'status', [],
	   [ map __($_), 'A   A', '?   A/bar', '?   A/deep', 'A   A/foo'], 'status - unknwon');

chdir('A');
is_output ($svk, 'status', ['../A'],
	   [ map __($_), 'A   ../A', '?   ../A/bar', '?   ../A/deep', 'A   ../A/foo'], 'status - unknwon');
chdir('..');
$svk->add ('A/deep');
$svk->commit ('-m', 'add a bunch for files');
overwrite_file ("A/foo", "fnord");
overwrite_file ("A/another", "fnord");
$svk->add ('A/another');
$svk->ps ('someprop', 'somevalue', 'A/foo', 'A/another');
is_output ($svk, 'status', [],
	   [ map __($_), 'MM  A/foo', 'A   A/another', '?   A/bar'], 'status - modified file and prop');
$svk->commit ('-m', 'some modification');
overwrite_file ("A/foo", "fnord\nmore");
$svk->commit ('-m', 'more modification');
rmtree (['A/deep']);
unlink ('A/another');
is_output ($svk, 'status', [],
	   [ map __($_), '!   A/another', '!   A/deep', '?   A/bar'], 'status - absent file and dir');
$svk->revert ('-R', 'A');
unlink ('A/deep/baz');
$svk->status;
$svk->delete ('A/deep');
$svk->delete ('A/another');
is_output ($svk, 'status', [],
	   [ map __($_), '?   A/bar', 'D   A/another', 'D   A/deep', 'D   A/deep/baz'], 'status - deleted file and dir');
$svk->revert ('-R', 'A');
overwrite_file ("A/foo", "foo");
TODO: {
local $TODO = "props should be merged, and A/nother shouldn't be schedule as add";
$svk->merge ('-r1:2', '//A', 'A');
is_output ($svk, 'status', [],
	   [ map __($_), 'C   A/foo', '?   A/bar'], 'status - conflict');
}
$svk->resolved ('A/foo');
$svk->revert ('-R', 'A');
overwrite_file ("A/foo", "foo");
$svk->merge ('-r2:3', '//A', 'A');
is_output ($svk, 'status', [],
	   [ map __($_), 'C   A/foo', '?   A/bar'], 'status - conflict');
$svk->revert ('A/foo');
$svk->ps ('someprop', 'somevalue', '.');
$svk->ps ('someprop', 'somevalue', 'A');
chdir ('A');
is_output ($svk, 'status', [],
	   [ map __($_), '?   bar', ' M  .']);
chdir ('..');
$svk->revert ('-R', '.');
$svk->ps ('someprop', 'somevalue', 'A/deep/baz');
is_output ($svk, 'status', ['A/deep'],
	   [__(' M  A/deep/baz')], 'prop only');
