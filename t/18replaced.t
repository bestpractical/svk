#!/usr/bin/perl -w
use Test::More tests => 10;
use strict;
our $output;
BEGIN { require 't/tree.pl' };
my ($xd, $svk) = build_test();
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');
my ($copath, $corpath) = get_copath ('replaced');
$svk->checkout ('//V', $copath);
$svk->rm ("$copath/A/be");
overwrite_file ("$copath/A/be", "foobar\n");
is_output ($svk, 'add', ["$copath/A/be"],
	   [__"R   $copath/A/be"]);
is_output ($svk, 'status', [$copath],
	   [__"R   $copath/A/be"]);
is_output ($svk, 'commit', ['-m', 'replace A/be', $copath],
	   ['Committed revision 4.']);
$svk->rm ("$copath/A");
mkdir ("$copath/A");
overwrite_file ("$copath/A/be", "foobar\n2nd replace\n");
overwrite_file ("$copath/A/neu", "foobar\n2nd replace\n");
# XXX: notify flush and cb_unknown ordering
is_output ($svk, 'add', ["$copath/A"],
	   [__"A   $copath/A/neu",
	    __"R   $copath/A",
	    __"R   $copath/A/be"]);
overwrite_file ("$copath/A/unused", "foobar\n2nd replace\n");
is_output ($svk, 'status', ["$copath"],
	   [__"R   $copath/A",
	    __"R   $copath/A/be",
	    __"A   $copath/A/neu",
	    __"?   $copath/A/unused",
	    __"D   $copath/A/Q",
	    __"D   $copath/A/Q/qu",
	    __"D   $copath/A/Q/qz"]);

is_output ($svk, 'add', ['-N', "$copath/A"],
	   [__("$copath/A already added.")]);
$svk->revert ('-R', $copath);
is_output ($svk, 'status', [$copath],
	   [__"?   $copath/A/neu",
	    __"?   $copath/A/unused"], 'revert replaced tree items');
unlink ("$copath/A/neu");
unlink ("$copath/A/unused");
$svk->rm ("$copath/A");
mkdir ("$copath/A");
overwrite_file ("$copath/A/be", "foobar\n2nd replace\n");
overwrite_file ("$copath/A/neu", "foobar\n2nd replace\n");
$svk->add ("$copath/A");
is_output ($svk, 'commit', ['-m', 'replace A/be', $copath],
	   ['Committed revision 5.']);
$svk->rm ("$copath/A");
$svk->status ($copath);
overwrite_file ("$copath/A", "dir replaced as file\n");
$svk->status ($copath);
is_output ($svk, 'add', ["$copath/A"],
	   [__"R   $copath/A"]);
TODO: {
local $TODO = 'file replacing dir';
is_output ($svk, 'status', [$copath],
	   [__"R   $copath/A",
	    __"D   $copath/A/be",
	    __"D   $copath/A/neu"], 'file replacing dir');
}
