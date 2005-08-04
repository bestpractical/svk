#!/usr/bin/perl -w
use Test::More tests => 1;
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
warn $output;
chdir($copath);
# simple case
$svk->cp('A' => 'A-cp');
warn $output;
$svk->ci(-m => 'copy A');
warn $output;
$svk->pull('//local');
warn $output;
is_ancestor($svk, '//local/A-cp', '//local/A', 4);
warn $output;
