#!/usr/bin/perl -w
use strict;
use Test::More tests => 24;
BEGIN { require 't/tree.pl' };

use SVK::Util qw( HAS_SYMLINK );

our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('symlink');

my @symlinks;
sub _symlink {
    my ($from, $to) = @_;
    return symlink($from => $to) if HAS_SYMLINK;
    overwrite_file ($to, "link $from");
    push @symlinks, $to;
}

sub _fix_symlinks {
    $svk->ps('svn:special' => '*', @symlinks) if @symlinks;
    @symlinks = ();
}

$svk->checkout ('//', $copath);
mkdir ("$copath/A");
overwrite_file ("$copath/A/bar", "foobar\n");
_symlink ("bar", "$copath/A/bar.lnk");
_symlink ('/tmp', "$copath/A/dir.lnk");
is_output ($svk, 'add', ["$copath/A"],
	   [__"A   $copath/A",
	    __"A   $copath/A/bar",
	    __"A   $copath/A/bar.lnk",
	    __"A   $copath/A/dir.lnk"], 'add symlinks');
_symlink ('/non-exists', "$copath/A/non.lnk");
is_output ($svk, 'add', ["$copath/A/non.lnk"],
	   [__("A   $copath/A/non.lnk")], 'dangling symlink');

#warn $output;
is_output ($svk, 'status', ["$copath/A"],
	   [__"A   $copath/A",
	    __"A   $copath/A/bar",
	    __"A   $copath/A/bar.lnk",
	    __"A   $copath/A/dir.lnk",
	    __"A   $copath/A/non.lnk"], 'status added symlinks');

_fix_symlinks();
$svk->commit ('-m', 'init', $copath);

rmtree [$copath];
is_output ($svk, 'checkout', ['//', $copath],
	   ["Syncing //(/) in $corpath to 1.",
	    __"A   $copath/A",
	    __"A   $copath/A/dir.lnk",
	    __"A   $copath/A/bar",
	    __"A   $copath/A/bar.lnk",
	    __"A   $copath/A/non.lnk"], 'checkout symlinks');

is_output ($svk, 'status', [$copath], [], 'unmodified status');

unlink ("$copath/A/dir.lnk");
_symlink ('.', "$copath/A/dir.lnk");

is_output ($svk, 'status', [$copath],
	   [__("M   $copath/A/dir.lnk")], 'modified status');

is_output ($svk, 'diff', [$copath],
	   [__('=== t/checkout/symlink/A/dir.lnk'),
	    '==================================================================',
	    __('--- t/checkout/symlink/A/dir.lnk  (revision 1)'),
	    __('+++ t/checkout/symlink/A/dir.lnk  (local)'),
	    '@@ -1 +1 @@',
	    '-link /tmp',
            '\ No newline at end of file',
            '+link .',
            '\ No newline at end of file'], 'modified diff');

$svk->revert ("$copath/A/dir.lnk");
is_output ($svk, 'status', [$copath], [], 'revert');

unlink ("$copath/A/dir.lnk");
_symlink ('.', "$copath/A/dir.lnk");

$svk->revert ('-R', $copath);
is_output ($svk, 'status', [$copath], [], 'revert');
$svk->cp ('//A/non.lnk', "$copath/non.lnk.cp");
ok (_l "$copath/non.lnk.cp", 'copy');

_fix_symlinks();
is_output ($svk, 'commit', ['-m', 'add copied symlink', $copath],
	   ['Committed revision 2.']);

$svk->cp ('-m', 'make branch', '//A', '//B');
# XXX: commit and then update will break checkout optimization,
# make a separate test for that
$svk->update ($copath);
unlink ("$copath/B/dir.lnk");
_symlink ('.', "$copath/B/dir.lnk");

_fix_symlinks();
$svk->commit ('-m', 'change something', "$copath/B");

$svk->smerge ('-C', '//B', "$copath/A");
is_output ($svk, 'smerge', ['--no-ticket', '//B', "$copath/A"],
	   ['Auto-merging (0, 4) /B to /A (base /A:1).',
	    __("U   $copath/A/dir.lnk")], 'merge');
is_output ($svk, 'diff', [$copath],
	   [__('=== t/checkout/symlink/A/dir.lnk'),
	    '==================================================================',
	    __('--- t/checkout/symlink/A/dir.lnk  (revision 4)'),
	    __('+++ t/checkout/symlink/A/dir.lnk  (local)'),
	    '@@ -1 +1 @@',
	    '-link /tmp',
            '\ No newline at end of file',
            '+link .',
            '\ No newline at end of file'], 'merge');

_symlink ('non', "$copath/B/new-non.lnk");
$svk->import ('--force', '-m', 'use import', '//', $copath);
unlink ("$copath/B/new-non.lnk");
$svk->revert ('-R', "$copath/B");
ok (_l "$copath/B/new-non.lnk", 'import sets auto prop too');

is_output ($svk, 'status', [$copath], [], 'import');

$svk->rm ("$copath/B/new-non.lnk");
is_output ($svk, 'status', [$copath],
	   [__('D   t/checkout/symlink/B/new-non.lnk')], 'delete');
overwrite_file ("$copath/B/new-non.lnk", "foobar\n");
is_output ($svk, 'add', ["$copath/B/new-non.lnk"],
	   [__('R   t/checkout/symlink/B/new-non.lnk')], 'replace symlink with normal file');

_fix_symlinks();
is_output ($svk, 'commit', ['-m', 'change to non-link', $copath],
	   ['Committed revision 6.']);
$svk->update ('-r5', $copath);
ok (_l "$copath/B/new-non.lnk", 'update from file to symlink');
$svk->update ($copath);
ok (-e "$copath/B/new-non.lnk", 'update from symlink to file');

$svk->rm ("$copath/B/new-non.lnk");
_symlink ('non', "$copath/B/new-non.lnk");
is_output ($svk, 'add', ["$copath/B/new-non.lnk"],
	   [__('R   t/checkout/symlink/B/new-non.lnk')], 'replace normal file with symlink');
is_output ($svk, 'st', [$copath],
	   [__('R   t/checkout/symlink/B/new-non.lnk')]);
is_output ($svk, 'commit', ['-m', 'change to non-link', $copath],
	   ['Committed revision 7.']);

unlink ("$copath/B/dir.lnk");
_symlink ('/tmp', "$copath/B/dir.lnk");
is_output ($svk, 'commit', ['-m', "change dir.lnk", "$copath/B/dir.lnk"],
	   ['Committed revision 8.']);

# XXX: test for conflicts resolving etc; XD should stop translating when conflicted
