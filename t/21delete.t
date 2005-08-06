#!/usr/bin/perl -w
use Test::More tests => 21;
use strict;
use File::Path;
BEGIN { require 't/tree.pl' };
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
is_output ($svk, 'rm', ['A/foo'],
	   [__"A/foo is scheduled, use 'svk revert'."]);
$svk->commit ('-m', 'init');

append_file ('A/foo', "modified.\n");
is_output ($svk, 'rm', ['A/foo'],
	   [__"A/foo is modified, use 'svk revert' first."]);
$svk->revert ('A/foo');
is_output ($svk, 'delete', ['A/foo'],
	   [__('D   A/foo')], 'delete - file');
ok (!-e 'A/foo', 'delete - copath deleted');
is_output ($svk, 'status', [],
	   [__('D   A/foo')], 'delete - status');

is_output ($svk, 'delete', ['A/foo'],
	   [__('D   A/foo')], 'delete file again');


$svk->revert ('-R', '.');

unlink ('A/foo');
is_output ($svk, 'delete', ['A/foo'],
	   [__('D   A/foo')], 'delete - file already unlinked');
is_output ($svk, 'status', [],
	   [__('D   A/foo')], 'delete - status');

$svk->revert ('-R', '.');
is_output ($svk, 'delete', ['A/foo', 'A/bar'],
		[__('D   A/foo'),
		 __('D   A/bar')]);
$svk->revert ('-R', '.');

is_output ($svk, 'delete', ['--keep-local', 'A/foo'],
	   [__('D   A/foo')], '');
ok (-e 'A/foo', 'copath not deleted');
is_output ($svk, 'status', [],
	   [__('D   A/foo')], 'copath not deleted');

is_output ($svk, 'delete', ["$corpath/A/foo"],
	   [__("D   $corpath/A/foo")], 'delete - file - abspath');
$svk->revert ('-R', '.');

overwrite_file ("A/deep/baz~", "foobar");
is_output ($svk, 'delete', ['A/deep'],
	   [map __($_),
	    'D   A/deep',
	    'D   A/deep/baz'], 'delete - ignore files');

is_output ($svk, 'delete', ['-m', 'rm directly', '//A/deep'],
	  ['Committed revision 2.'], 'rm directly');

$svk->mkdir (-m => 'something', '//A/something');

$svk->up;
rmtree ('A/something');
is_output ($svk, 'st', [],
	   [__('!   A/something')]);
is_output ($svk, 'rm', ['A/something'],
	   [__('D   A/something')]);

overwrite_file ('A/stalled', "foo");
is_output ($svk, 'rm', ['A/stalled'],
	   [__('A/stalled is not under version control.')]);

is_output ($svk, 'rm', ['//A/deep', '//A/bad'],
	   [qr'not supported']);

is_output ($svk, 'rm', ['A/deep', '//A/bad'],
	   [qr'not supported']);

