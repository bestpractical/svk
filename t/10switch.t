#!/usr/bin/perl -w
use strict;
use Test::More tests => 8;
require 't/tree.pl';

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test();
our $output;
my $tree = create_basic_tree ($xd, '//');

my ($copath, $corpath) = get_copath ('switch');

is_output_like ($svk, 'switch', [], qr'SYNOPSIS');
$svk->cp ('-r1m', 'copy', '//A', '//A-branch');

$svk->checkout ('//A-branch', $copath);

is_output_like ($svk, 'switch', ['//A-branch', '.', 'foo'], qr'SYNOPSIS');
overwrite_file ("$copath/Q/qu", "first line in qu\nlocally modified on branch\n2nd line in qu\n");

#$svk->switch ('-C', '//A');
is_output ($svk, 'switch', ['//A', $copath],
	   ["Syncing //A-branch(/A-branch) in $corpath to 3.",
	    map __($_),
	    "D   $copath/P"]);
ok ($xd->{checkout}->get ($corpath)->{depotpath} eq  '//A', 'switched');
is_file_content ("$copath/Q/qu", "first line in qu\nlocally modified on branch\n2nd line in qu\n");
chdir ($copath);
is_output ($svk, 'switch', ['//A-branch'],
	   ["Syncing //A(/A) in $corpath to 3.",
	    map __($_),
	    'A   P',
	    'A   P/pe',
	   ]);

is_output ($svk, 'switch', ['//A-branch', 'P'],
	   ['Can only switch checkout root.']);

is_output ($svk, 'switch', ['--detach'],
	   [__("Checkout path '$corpath' detached.")]);
