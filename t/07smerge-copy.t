#!/usr/bin/perl -w
use Test::More tests => 7;
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
$svk->mkdir('//trunk/A/new', -m => 'new dir');
$svk->cp('//trunk/A' => '//trunk/A-cp-again', -m => 'more');

# expanded, because copy source is within the merge as well.
# or should be be more aggressive to copy from closer source
# then apply the delta by ourself?
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

