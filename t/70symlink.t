#!/usr/bin/perl -w
# XXX: skip on platform not supporting symlinks
use Test::More tests => 18;
use strict;
use File::Path;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('symlink');

$svk->checkout ('//', $copath);
mkdir ("$copath/A");
overwrite_file ("$copath/A/bar", "foobar\n");
symlink ("bar", "$copath/A/bar.lnk");
symlink ('/tmp', "$copath/A/dir.lnk");
symlink ('/non-exists', "$copath/A/non.lnk");
is_output ($svk, 'add', ["$copath/A"],
	   ["A   $copath/A",
	    "A   $copath/A/bar",
	    "A   $copath/A/bar.lnk",
	    "A   $copath/A/dir.lnk",
	    "A   $copath/A/non.lnk"], 'add symlinks');
#warn $output;
is_output ($svk, 'status', ["$copath/A"],
	   ["A   $copath/A",
	    "A   $copath/A/bar",
	    "A   $copath/A/bar.lnk",
	    "A   $copath/A/dir.lnk",
	    "A   $copath/A/non.lnk"], 'status added symlinks');
$svk->commit ('-m', 'init', $copath);

rmtree [$copath];
is_output ($svk, 'checkout', ['//', $copath],
	   ["Syncing //(/) in $corpath to 1.",
	    "A   $copath/A",
	    "A   $copath/A/dir.lnk",
	    "A   $copath/A/bar",
	    "A   $copath/A/bar.lnk",
	    "A   $copath/A/non.lnk"], 'checkout symlinks');

is_output ($svk, 'status', [$copath], [], 'unmodified status');

unlink ("$copath/A/dir.lnk");
symlink ('.', "$copath/A/dir.lnk");
is_output ($svk, 'status', [$copath],
	   ["M   $copath/A/dir.lnk"], 'modified status');

is_output ($svk, 'diff', [$copath],
	   ['=== t/checkout/symlink/A/dir.lnk',
	    '==================================================================',
	    '--- t/checkout/symlink/A/dir.lnk  (revision 1)',
	    '+++ t/checkout/symlink/A/dir.lnk  (local)',
	    '@@ -1 +1 @@',
	    '-link /tmp+link .'], 'modified diff');

$svk->revert ("$copath/A/dir.lnk");
is_output ($svk, 'status', [$copath], [], 'revert');

unlink ("$copath/A/dir.lnk");
symlink ('.', "$copath/A/dir.lnk");

$svk->revert ('-R', $copath);
is_output ($svk, 'status', [$copath], [], 'revert');
$svk->cp ('//A/non.lnk', "$copath/non.lnk.cp");
ok (-l "$copath/non.lnk.cp", 'copy');
$svk->commit ('-m', 'add copied symlink', $copath);
$svk->cp ('-m', 'make branch', '//A', '//B');
# XXX: commit and then update will break checkout optimization,
# make a separate test for that
$svk->update ($copath);
unlink ("$copath/B/dir.lnk");
symlink ('.', "$copath/B/dir.lnk");

$svk->commit ('-m', 'change something', "$copath/B");

$svk->smerge ('-C', '//B', "$copath/A");
is_output ($svk, 'smerge', ['--no-ticket', '//B', "$copath/A"],
	   ['Auto-merging (1, 4) /B to /A (base /A:1).',
	    "U   $copath/A/dir.lnk"], 'merge');
is_output ($svk, 'diff', [$copath],
	   ['=== t/checkout/symlink/A/dir.lnk',
	    '==================================================================',
	    '--- t/checkout/symlink/A/dir.lnk  (revision 4)',
	    '+++ t/checkout/symlink/A/dir.lnk  (local)',
	    '@@ -1 +1 @@',
	    '-link /tmp+link .'], 'merge');

symlink ('non', "$copath/B/new-non.lnk");
$svk->import ('--force', '-m', 'use import', '//', $copath);
unlink ("$copath/B/new-non.lnk");
$svk->revert ('-R', "$copath/B");
ok (-l "$copath/B/new-non.lnk", 'import sets auto prop too');

is_output ($svk, 'status', [$copath], [], 'import');

$svk->rm ("$copath/B/new-non.lnk");
is_output ($svk, 'status', [$copath],
	   ['D   t/checkout/symlink/B/new-non.lnk'], 'delete');
overwrite_file ("$copath/B/new-non.lnk", "foobar\n");
is_output ($svk, 'add', ["$copath/B/new-non.lnk"],
	   ['R   t/checkout/symlink/B/new-non.lnk'], 'replace symlink with normal file');
is_output ($svk, 'commit', ['-m', 'change to non-link', $copath],
	   ['Committed revision 6.']);
$svk->update ('-r5', $copath);
ok (-l "$copath/B/new-non.lnk", 'update from file to symlink');
$svk->update ($copath);
ok (-e "$copath/B/new-non.lnk", 'update from symlink to file');

# XXX: test for conflicts resolving etc; XD should stop translating when conflicted
