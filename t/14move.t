#!/usr/bin/perl -w
use Test::More tests => 2;
use strict;
our $output;
BEGIN { require 't/tree.pl' };
my ($xd, $svk) = build_test('foo');
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');

my ($copath, $corpath) = get_copath ('move');

$svk->checkout ('//V', $copath);

is_output ($svk, 'move', ["$copath/A/Q", "$copath/A/be", $copath],
	   [__"D   $copath/A/Q",
	    __"D   $copath/A/Q/qu",
	    __"D   $copath/A/Q/qz",
	    __"A   $copath/Q",
	    __"A   $copath/Q/qu",
	    __"A   $copath/Q/qz",
	    __"D   $copath/A/be",
	    __"A   $copath/be"]);

is_output ($svk, 'status', [$copath],
	   [__"D   $copath/A/Q",
	    __"D   $copath/A/Q/qu",
	    __"D   $copath/A/Q/qz",
	    __"D   $copath/A/be",
	    __"A + $copath/Q",
	    __"A + $copath/be"]);

$svk->commit ('-m', 'move in checkout committed', $copath);
