#!/usr/bin/perl -w
use Test::More tests => 20;
use strict;
BEGIN { require 't/tree.pl' };
our $output;
my ($xd, $svk) = build_test();
$svk->mkdir ('-m', 'init', '//V');
$svk->mkdir ('-m', 'init', '//V-3.1');
my $tree = create_basic_tree ($xd, '//V');
my $tree2 = create_basic_tree ($xd, '//V-3.1');
my ($copath, $corpath) = get_copath ('checkout');
mkdir ($copath);

my $cofile = __"$copath/co-root/V-3.1/A/Q/qz";
is_output_like ($svk, 'checkout', ['//', "$copath/co-root"],
		qr{A   \Q$cofile\E},
		'checkout - report path');
ok (-e "$copath/co-root/V/A/Q/qu");

$svk->checkout ('//V/A', "$copath/co-root-a");
ok (-e "$copath/co-root-a/Q/qu");

$svk->checkout ('//V-3.1', "$copath/co-root-v3.1");
ok (-e "$copath/co-root-v3.1/A/Q/qu");

chdir ($copath);
$svk->checkout ('//V-3.1');
ok (-e 'V-3.1/A/Q/qu');
is_output_like ($svk, 'checkout', ['//'], qr"don't know where to checkout");

is_output_like ($svk, 'checkout', ['//V-3.1'], qr'already exists');
is_output_like ($svk, 'checkout', ['//V-3.1', 'V-3.1/l2'], qr'overlapping checkout');

$svk->checkout ('-r5', '//V-3.1', 'V-3.1-r5');
ok (-e 'V-3.1-r5/A/P/pe');

is_output ($svk, 'checkout', ['-Nr5', '//V-3.1', 'V-3.1-nr'],
	   ["Syncing //V-3.1(/V-3.1) in ".__"$corpath/V-3.1-nr to 5.",
	    __('A   V-3.1-nr/me')], 'checkout - non-recursive');

ok (!-e 'V-3.1-nr/A');
ok (-e 'V-3.1-nr/me');

is_output ($svk, 'checkout', ['//V-3.1/A/Q/qu'],
	   ["Syncing //V-3.1/A/Q/qu(/V-3.1/A/Q/qu) in ".__"$corpath/qu to 6.",
	    'A   qu']);
ok (-e 'qu');

is_output ($svk, 'checkout', ['//V-3.1/A/Q/qu', 'boo'],
	   ["Syncing //V-3.1/A/Q/qu(/V-3.1/A/Q/qu) in ".__"$corpath/boo to 6.",
	    'A   boo']);
ok (-e 'boo');

is_output ($svk, 'checkout', ['//V-3.1/A/Q', "../checkout/just-q"],
	   ["Syncing //V-3.1/A/Q(/V-3.1/A/Q) in ".__"$corpath/just-q to 6.",
	    __('A   ../checkout/just-q/qu'),
	    __('A   ../checkout/just-q/qz'),
	    __(' U  ../checkout/just-q'),
	   ], 'checkout report');

is_output ($svk, 'checkout', ['//V-3.1/A/Q/', "../checkout/just-q-slash"],
	   ["Syncing //V-3.1/A/Q/(/V-3.1/A/Q) in ".__"$corpath/just-q-slash to 6.",
	    __('A   ../checkout/just-q-slash/qu'),
	    __('A   ../checkout/just-q-slash/qz'),
	    __(' U  ../checkout/just-q-slash'),
	   ], 'checkout report');

is_output ($svk, 'checkout', ['//V-3.1/A/Q', "../checkout/just-q-slashco/"],
	   ["Syncing //V-3.1/A/Q(/V-3.1/A/Q) in ".__"$corpath/just-q-slashco to 6.",
	    __('A   ../checkout/just-q-slashco/qu'),
	    __('A   ../checkout/just-q-slashco/qz'),
	    __(' U  ../checkout/just-q-slashco'),
	   ], 'checkout report');


is_output_like ($svk, 'checkout', ['//V-3.1-non'],
		qr'not exist');
