#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl';};
plan tests => 12;
our $output;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test();

my $tree = create_basic_tree ($xd, '//');
my ($copath, $corpath) = get_copath ('view');

$svk->ps ('-m', 'my view', 'svk:view:myview',
	  '/
 -B
 -A
#  AQ/Q/qz /A/Q/qz
  BSP  /B/S/P
', '//');
is_output($svk, 'ls', ['//^myview'],
	  ['BSP/', 'C/', 'D/', 'me']);

is_output($svk, 'checkout', ['//^myview', $copath],
	  ['Syncing //(/) in '.__($corpath)." to 3.",
	   map { __($_) } "A   $copath/me",
	   "A   $copath/C",
	   "A   $copath/C/R",
	   "A   $copath/D",
	   "A   $copath/D/de",
	   "A   $copath/BSP",
	   "A   $copath/BSP/pe",
	   " U  $copath"]);

TODO: {
local $TODO = 'intermediate directory for A/Q/qz reviving map.';
ok (-d "$copath/AQ/Q");
}
ok (!-e "$copath/A/Q/qu");
ok (-e "$copath/BSP");
is_output ($svk, 'status', [$copath], []);

append_file ("$copath/BSP/pe", "foobar\n");
is_output ($svk, 'st', [$copath],
	   [__"M   $copath/BSP/pe"]);

overwrite_file ("$copath/BSP/newfile", "foobar\n");
is_output($svk, 'add', ["$copath/BSP/newfile"],
	  [__"A   $copath/BSP/newfile"]);

is_output($svk, 'rm', ["$copath/D"],
	  [map {__($_)}
	   "D   $copath/D",
	   "D   $copath/D/de"]);

is_output($svk, 'st', [$copath],
	  [map {__($_)}
	   "M   $copath/BSP/pe",
	   "A   $copath/BSP/newfile",
	   "D   $copath/D",
	   "D   $copath/D/de",
	  ]);
is_output ($svk, 'revert', ['-R', $copath],
	   ["Reverted $copath/BSP/pe",
	    "Reverted $copath/BSP/newfile",
	    "Reverted $copath/D",
	    "Reverted $copath/D/de"]);

$svk->add ("$copath/BSP/newfile");
append_file ("$copath/BSP/pe", "foobar\n");

$svk->commit ('-m', 'commit from view', $copath);

rmtree [$copath];

$svk->checkout ('//', $copath);
#warn $output;
is_output($svk, 'switch', ['//^myview', $copath],
	  [ "Syncing //(/) in $corpath to 3.",
	    map { __($_) }
	    "A   $copath/BSP",
	    "A   $copath/BSP/pe",
	    "D   $copath/A",
	    "D   $copath/B"]);
