#!/usr/bin/perl
use strict;
use SVN::XD;
use Test::More qw(no_plan);
require 't/tree.pl';
package main;

$svk::info = build_test ('');

my $tree = create_basic_tree ('//');
my ($copath, $corpath) = get_copath ('keyword');
svk::checkout ('//', $copath);

is_file_content ("$copath/A/be",
		 "\$Rev: 1\$\nfirst line in be\n2nd line in be\n",
		 'basic Id');

append_file ("$copath/A/be", "some more\n");

svk::commit ('-m', 'some modifications', $copath);

TODO: {
local $TODO = "implement checkout file update after commit";

is_file_content ("$copath/A/be",
		 "\$Rev: 3\$\nfirst line in be\n2nd line in be\n",
		 'commit Id');
};

append_file ("$copath/A/be", "more and more\n");

svk::diff ($copath);
