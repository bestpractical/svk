#!/usr/bin/perl -w
use strict;
use Test::More tests => 9;
require 't/tree.pl';

my ($xd, $svk) = build_test();

my $tree = create_basic_tree ($xd, '//');
my ($copath, $corpath) = get_copath ('keyword');
our $output;
$svk->checkout ('//', $copath);

is_file_content ("$copath/A/be",
		 "\$Rev: 1 \$ \$Rev: 1 \$\n\$Revision: #2 \$\nfirst line in be\n2nd line in be\n",
		 'basic Id');
append_file ("$copath/A/be", "some more\n");
$svk->ps ('svn:executable', 'on', "$copath/A/be");
ok (-x "$copath/A/be", 'svn:excutable effective after ps');
$svk->commit ('-m', 'some modifications', $copath);
ok (-x "$copath/A/be", 'take care of svn:executable after commit');

my $newcontent = "\$Rev: 3 \$ \$Rev: 3 \$\n\$Revision: #3 \$\nfirst line in be\n2nd line in be\nsome more\n";

is_file_content ("$copath/A/be", $newcontent, 'commit Id');

append_file ("$copath/A/be", "some more\n");
$svk->revert ("$copath/A/be");
is_file_content ("$copath/A/be", $newcontent, 'commit Id');

ok (-x "$copath/A/be", 'take care of svn:executable after revert');
append_file ("$copath/A/be", "some more\n");
$svk->commit ('-m', 'some more modifications', $copath);

$svk->update ('-r', 3, $copath);
ok (-x "$copath/A/be", 'take care of svn:executable after update');

is_output_like ($svk, 'update', ['-r', 2, $copath], qr|^UU  \Q$copath\E/A/be$|m,
		'keyword does not cause merge');

ok (!-x "$copath/A/be", 'take care of removing svn:executable after update');
