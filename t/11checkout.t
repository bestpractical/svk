#!/usr/bin/perl
use Test::More tests => 8;
use strict;
require 't/tree.pl';
use SVK::Command;
our $output;
my ($xd, $svk) = build_test();
$svk->mkdir ('-m', 'init', '//V');
$svk->mkdir ('-m', 'init', '//V-3.1');
my $tree = create_basic_tree ($xd, '//V');
my $tree2 = create_basic_tree ($xd, '//V-3.1');
my ($copath, $corpath) = get_copath ('checkout');
mkdir ($copath);

$svk->checkout ('//', "$copath/co-root");
ok (-e "$copath/co-root/V/A/Q/qu");

$svk->checkout ('//V/A', "$copath/co-root-a");
ok (-e "$copath/co-root-a/Q/qu");

$svk->checkout ('//V-3.1', "$copath/co-root-v3.1");
ok (-e "$copath/co-root-v3.1/A/Q/qu");

chdir ($copath);
$svk->checkout ('//V-3.1');
ok (-e 'V-3.1/A/Q/qu');
$svk->checkout ('//');
ok ($@ =~ qr"don't know where to checkout");

$svk->checkout ('//V-3.1');
ok ($@ =~ qr'already exists');
$svk->checkout ('//V-3.1', 'V-3.1/l2');
ok ($@ =~ qr'overlapping checkout');

$svk->checkout ('-r5', '//V-3.1', 'V-3.1-r5');
ok (-e 'V-3.1-r5/A/P/pe');
