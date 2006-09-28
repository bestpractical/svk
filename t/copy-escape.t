#!/usr/bin/perl -w
use Test::More tests => 3;
use strict;
our $output;
BEGIN { require 't/tree.pl' };
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('replaced');

# escaped chars
is_output($svk, 'mkdir', [-m => 'mkdir', -p => '//foo/blah%2Ffnord'],
	  ['Committed revision 1.']);

is_output($svk, 'cp', [-m => 'cp', '//foo/blah%2Ffnord', "//foo/baz%2Ffnord"],
	  ['Committed revision 2.']);

is_output($svk, 'ls', ['//foo'], ['baz%2Ffnord/', 'blah%2Ffnord/']);

