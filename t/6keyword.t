#!/usr/bin/perl
use strict;
use Test::More tests => 4;
require 't/tree.pl';

my ($xd, $svk) = build_test('');

my $tree = create_basic_tree ($xd, '//');
my ($copath, $corpath) = get_copath ('keyword');
$svk->checkout ('//', $copath);

is_file_content ("$copath/A/be",
		 "\$Rev: 1 \$ \$Rev: 1 \$\nfirst line in be\n2nd line in be\n",
		 'basic Id');

append_file ("$copath/A/be", "some more\n");
$svk->ps ('svn:executable', 'on', "$copath/A/be");
$svk->commit ('-m', 'some modifications', $copath);

my $newcontent = "\$Rev: 3 \$ \$Rev: 3 \$\nfirst line in be\n2nd line in be\nsome more\n";

is_file_content ("$copath/A/be", $newcontent, 'commit Id');

append_file ("$copath/A/be", "some more\n");
$svk->revert ("$copath/A/be");
is_file_content ("$copath/A/be", $newcontent, 'commit Id');

TODO: {
local $TODO = "take care of svn:executable after commit";

ok (-x "$copath/A/be");
};

append_file ("$copath/A/be", "more and more\n");

