#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl' };
plan_svm tests => 2;
our $output;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');

my $tree = create_basic_tree ($xd, '/test/');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);

my $uri = uri($srepospath);

$svk->mirror ('//test-A', "$uri/A");
is_output ($svk, 'sync', ['--skipto', 'HEAD', '//test-A'],
	   ["Syncing $uri/A",
	    'Retrieving log information from 2 to 2',
	    'Committed revision 2 from revision 2.']);

$svk->rm ('-m', 'redo mirror', '//test-A/');
$svk->mirror ('//test-A', "$uri/A");

$svk->mkdir ('-m', 'oh ya', '/test/Z');

# find the proper HEAD
is_output ($svk, 'sync', ['--skipto', 'HEAD', '//test-A'],
	   ["Syncing $uri/A",
	    'Retrieving log information from 2 to 2',
	    'Committed revision 6 from revision 2.']);
