#!/usr/bin/perl
use Test::More tests => 7;
use strict;
our $output;
require 't/tree.pl';
use SVK::Command;
my ($xd, $svk) = build_test();
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');
my ($copath, $corpath) = get_copath ('replaced');
$svk->checkout ('//V', $copath);
$svk->rm ("$copath/A/be");
overwrite_file ("$copath/A/be", "foobar\n");
is_output ($svk, 'add', ["$copath/A/be"],
	   ["R   $copath/A/be"]);
is_output ($svk, 'status', [$copath],
	   ["R   $copath/A/be"]);
is_output ($svk, 'commit', ['-m', 'replace A/be', $copath],
	   ['Committed revision 4.']);
$svk->rm ("$copath/A");
mkdir ("$copath/A");
overwrite_file ("$copath/A/be", "foobar\n2nd replace\n");
overwrite_file ("$copath/A/neu", "foobar\n2nd replace\n");
# XXX: notify flush and cb_unknown ordering
is_output ($svk, 'add', ["$copath/A"],
	   ["A   $copath/A/neu",
	    "R   $copath/A",
	    "R   $copath/A/be"]);
overwrite_file ("$copath/A/unused", "foobar\n2nd replace\n");
is_output ($svk, 'status', ["$copath"],
	   ["R   $copath/A",
	    "R   $copath/A/be",
	    "A   $copath/A/neu",
	    "?   $copath/A/unused",
	    "D   $copath/A/Q",
	    "D   $copath/A/Q/qu",
	    "D   $copath/A/Q/qz"]);

$svk->revert ('-R', $copath);
is_output ($svk, 'status', [$copath],
	   ["?   $copath/A/neu",
	    "?   $copath/A/unused"], 'revert replaced tree items');
unlink ("$copath/A/neu");
unlink ("$copath/A/unused");
$svk->rm ("$copath/A");
mkdir ("$copath/A");
overwrite_file ("$copath/A/be", "foobar\n2nd replace\n");
overwrite_file ("$copath/A/neu", "foobar\n2nd replace\n");
$svk->add ("$copath/A");
is_output ($svk, 'commit', ['-m', 'replace A/be', $copath],
	   ['Committed revision 5.']);
