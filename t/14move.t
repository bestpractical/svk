#!/usr/bin/perl -w
use Test::More tests => 2;
use strict;
our $output;
require 't/tree.pl';
my ($xd, $svk) = build_test('foo');
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');

my ($copath, $corpath) = get_copath ('move');

$svk->checkout ('//V', $copath);

is_output ($svk, 'move', ["$copath/A/Q", "$copath/A/be", $copath],
	   ["D   $copath/A/Q",
	    "D   $copath/A/Q/qu",
	    "D   $copath/A/Q/qz",
	    "A   $copath/Q",
	    "A   $copath/Q/qu",
	    "A   $copath/Q/qz",
	    "D   $copath/A/be",
	    "A   $copath/be"]);

is_output ($svk, 'status', [$copath],
	   ["D   $copath/A/Q",
	    "D   $copath/A/Q/qu",
	    "D   $copath/A/Q/qz",
	    "D   $copath/A/be",
	    "A + $copath/Q",
	    "A + $copath/be"]);

$svk->commit ('-m', 'move in checkout committed', $copath);
