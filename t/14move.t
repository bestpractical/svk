#!/usr/bin/perl -w
use Test::More tests => 8;
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
is_output ($svk, 'status', [$copath], []);
is_output ($svk, 'mv', ["$copath/Q/", "$copath/Q-new/"],
	   [__"D   $copath/Q",
	    __"D   $copath/Q/qu",
	    __"D   $copath/Q/qz",
	    __"A   $copath/Q-new",
	    __"A   $copath/Q-new/qu",
	    __"A   $copath/Q-new/qz"]);

is_output ($svk, 'status', [$copath],
	   [__"A + $copath/Q-new",
	    __"D   $copath/Q",
	    __"D   $copath/Q/qu",
	    __"D   $copath/Q/qz"]);

is_output ($svk, 'mv', ["$copath/be", "$copath/Q-new/"],
	   [__"D   $copath/be",
	    __"A   $copath/Q-new/be"]);

is_output ($svk, 'mv', ["$copath/B/fe", "$copath/Q-new/fe"],
	   [__"D   $copath/B/fe",
	    __"A   $copath/Q-new/fe"]);
$svk->revert ("$copath/B/fe", "$copath/Q-new/fe");

is_output ($svk, 'mv', ["$copath/B/fe", "$copath/Q-new/be"],
	   [__"Path $copath/Q-new/be already exists."]);
