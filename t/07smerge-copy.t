#!/usr/bin/perl -w
use Test::More tests => 15;
use strict;
use File::Path;
use Cwd;
BEGIN { require 't/tree.pl' };


my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('smerge-copy');
$svk->mkdir ('-m', 'trunk', '//trunk');
my $tree = create_basic_tree ($xd, '//trunk');
$svk->cp ('-m', 'branch', '//trunk', '//local');

$svk->checkout ('//trunk', $copath);
chdir($copath);
# simple case
$svk->cp('A' => 'A-cp');
$svk->ci(-m => 'copy A');

is_output($svk, 'pull', ['//local'],
	  ['Auto-merging (3, 5) /trunk to /local (base /trunk:3).',
	   'A + A-cp',
	   qr'New merge ticket: .*:/trunk:5',
	   'Committed revision 6.'
	  ]);

is_ancestor($svk, '//local/A-cp', '/local/A', 4, '/trunk/A', 3);

# expanded, because copy source is within the merge as well.
# or should be be more aggressive to copy from closer source
# then apply the delta by ourself?

$svk->mkdir('//trunk/A/new', -m => 'new dir');
$svk->cp('//trunk/A' => '//trunk/A-cp-again', -m => 'more');

$svk->pull('//local');
is_ancestor($svk, '//local/A-cp-again');

$svk->cp('//trunk/A-cp-again' => '//trunk/A-cp-more', -m => 'more');

is_output($svk, 'pull', ['//local'],
	  ['Auto-merging (8, 10) /trunk to /local (base /trunk:8).',
	   'A + A-cp-more',
	   qr'New merge ticket: .*:/trunk:10',
	   'Committed revision 11.']);

is_ancestor($svk, '//local/A-cp-more', '/local/A-cp-again', 9);
$svk->up;

# replace with history.  this is very tricky, because we have to use
# ignore_ancestry in dir_delta, and this makes the replace an
# modification, rather than an add.

$svk->rm('A/be');
$svk->cp('A/Q/qu', 'A/be');
$svk->ci(-m => 'replace A/be');

is_output($svk, 'pull', ['//local'],
	  ['Auto-merging (10, 12) /trunk to /local (base /trunk:10).',
	   'R + A/be',
	   qr'New merge ticket: .*:/trunk:12',
	   'Committed revision 13.']);

# note that it's copied from 6, not 4.  should be normalised when
# trying to copy
is_ancestor($svk, '//local/A/be',
	    '/local/A/Q/qu', 4,
	    '/trunk/A/Q/qu', 2);


$svk->mv('A/Q/qu', 'A/quz');
$svk->ci(-m => 'move A/Q/qu');

is_output($svk, 'pull', ['//local'],
	  ['Auto-merging (12, 14) /trunk to /local (base /trunk:12).',
	   'A + A/quz',
	   'D   A/Q/qu',
	   qr'New merge ticket: .*:/trunk:14',
	   'Committed revision 15.']);

is_ancestor($svk, '//local/A/quz',
	    '/local/A/Q/qu', 4,
	    '/trunk/A/Q/qu', 2);


# copy and modify
$svk->cp('A/quz', 'A/quz-mod');
append_file('A/quz-mod', "modified after copy\n");

$svk->ci(-m => 'copy file with modification');

is_output($svk, 'pull', ['//local'],
	  ['Auto-merging (14, 16) /trunk to /local (base /trunk:14).',
	   'A + A/quz-mod',
	   qr'New merge ticket: .*:/trunk:16',
	   'Committed revision 17.']);

is_file_content('A/quz-mod',
		"first line in qu\n2nd line in qu\nmodified after copy\n");

# copy directory and modify
$svk->cp('B', 'B-mod');

append_file('B-mod/fe', "modified after copy\n");
append_file('B-mod/S/P/pe', "modified after copy\n");
overwrite_file('B-mod/S/new', "new file\n");
$svk->add('B-mod/S/new');
$svk->ci(-m => 'copy file with modification');

TODO: {
local $TODO = 'copy+mod inside directoy reqires merge editor cb to use txn or to resolve to cp source.';
is_output($svk, 'pull', ['//local'],
	  ['Auto-merging (16, 18) /trunk to /local (base /trunk:16).',
	   'A + B-mod',
	   'M   B-mod/fe',
	   'M   B-mod/S/pe',
	   'A   B-mod/S/new',
	   qr'New merge ticket: .*:/trunk:18',
	   'Committed revision 19.']);
is_output ($svk, 'sw', ['//local'],
	   ['Syncing //trunk(/trunk) in /Users/clkao/work/svk-smcp/t/checkout/smerge-copy to 19.'], 'should be no differences.');

}

$svk->mv('//trunk/B', '//trunk/B-tmp', -m => 'B -> tmp');
$svk->mv('//trunk/A', '//trunk/B', -m => 'A -> B');
$svk->mv('//trunk/B-tmp', '//trunk/A', -m => 'B-tmp -> A');

is_output($svk, 'pull', ['//local'],
	  ['Auto-merging (18, 22) /trunk to /local (base /trunk:18).',
	   'R + A',
	   'R + B',
	   qr'New merge ticket: .*:/trunk:22',
	   'Committed revision 23.']);

$svk->cp('//trunk' => '//local-new', -m => 'new branch');
$svk->sw('//local-new');
$svk->cp('B' => 'B-fromlocal');
$svk->ci(-m => 'a copy at local');

TODO: {
local $TODO = 'base ne src merge should resolve copy properly.';

is_output($svk, 'push', [],
	  ['Auto-merging (0, 25) /local-new to /trunk (base /trunk:22).',
	   '===> Auto-merging (0, 24) /local-new to /trunk (base /trunk:22).',
	   'Empty merge.',
	   '===> Auto-merging (24, 25) /local-new to /trunk (base /trunk:22).',
	   'A + B-fromlocal',
	   qr'New merge ticket: .*:/local-new:25',
	   'Committed revision 26.']);

}

