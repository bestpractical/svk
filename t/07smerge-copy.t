#!/usr/bin/perl -w
use Test::More tests => 4;
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
$svk->pull('//local');
is_ancestor($svk, '//local/A-cp', '/local/A', 4, '/trunk/A', 3);

$svk->mkdir('//trunk/A/new', -m => 'new dir');
$svk->cp('//trunk/A' => '//trunk/A-cp-again', -m => 'more');

# expanded, because copy source is within the merge as well.
# or should be be more aggressive to copy from closer source
# then apply the delta by ourself?
$svk->pull('//local');
is_ancestor($svk, '//local/A-cp-again');

$svk->cp('//trunk/A-cp-again' => '//trunk/A-cp-more', -m => 'more');
$svk->pull('//local');
is_ancestor($svk, '//local/A-cp-more', '/local/A-cp-again', 9);

$svk->up;

$svk->rm('A/be');
$svk->cp('A/Q/qu', 'A/be');
$svk->ci(-m => 'replace A/be');

$svk->pull('//local');
is_ancestor($svk, '//local/A/be', '/local/A/Q/qu', 9);
