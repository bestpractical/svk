#!/usr/bin/perl -w
use strict;
use Test::More tests => 16;
require 't/tree.pl';

my ($xd, $svk) = build_test();

my $tree = create_basic_tree ($xd, '//');
my ($copath, $corpath) = get_copath ('keyword');
our $output;
$svk->checkout ('//', $copath);

is_file_content ("$copath/A/be",
		 "\$Rev: 1 \$ \$Rev: 1 \$\n\$Revision: #1 \$\nfirst line in be\n2nd line in be\n",
		 'basic Id');
append_file ("$copath/A/be", "some more\n");
$svk->ps ('svn:executable', 'on', "$copath/A/be");
ok (-x "$copath/A/be", 'svn:excutable effective after ps');
$svk->commit ('-m', 'some modifications', $copath);
ok (-x "$copath/A/be", 'take care of svn:executable after commit');

my $newcontent = "\$Rev: 3 \$ \$Rev: 3 \$\n\$Revision: #2 \$\nfirst line in be\n2nd line in be\nsome more\n";

is_file_content ("$copath/A/be", $newcontent, 'commit Id');

append_file ("$copath/A/be", "some more\n");
$svk->revert ("$copath/A/be");
is_file_content ("$copath/A/be", $newcontent, 'commit Id');

ok (-x "$copath/A/be", 'take care of svn:executable after revert');
append_file ("$copath/A/be", "some more\n");
$svk->commit ('-m', 'some more modifications', $copath);

is_file_content ("$copath/A/be",
		 "\$Rev: 4 \$ \$Rev: 4 \$\n\$Revision: #3 \$\nfirst line in be\n2nd line in be\nsome more\nsome more\n");
$svk->update ('-r', 3, $copath);
ok (-x "$copath/A/be", 'take care of svn:executable after update');
is_file_content ("$copath/A/be", $newcontent, 'commit Id');

is_output_like ($svk, 'update', ['-r', 2, $copath], qr|^UU  \Q$copath\E/A/be$|m,
		'keyword does not cause merge');

ok (!-x "$copath/A/be", 'take care of removing svn:executable after update');
overwrite_file ("$copath/A/foo", "\$Rev: 999 \$");
$svk->add ("$copath/A/foo");
$svk->commit ('-m', 'adding a file', $copath);

is_file_content ("$copath/A/foo", "\$Rev: 999 \$", 'commit unreverted ref');
append_file ("$copath/A/foo", "some more\n");
$svk->ps ('svn:keywords', 'URL Author Rev Date Id FileRev', "$copath/A/foo");
$svk->commit ('-m', 'appending a file and change props', $copath);
is_output ($svk, 'st', ["$copath/A/foo"], [], 'commit does keyword expansion');

mkdir ("$copath/le");
overwrite_file ("$copath/le/dos", "dos\n");
overwrite_file ("$copath/le/lf", "unix\n");
overwrite_file ("$copath/le/native", "native\n");
$svk->add ("$copath/le");
$svk->ps ('svn:eol-style', 'CRLF', "$copath/le/dos");
$svk->ps ('svn:eol-style', 'native', "$copath/le/native");
$svk->ps ('svn:eol-style', 'LF', "$copath/le/unix");
$svk->commit ('-m', 'test line ending', $copath);
is_file_content ("$copath/le/dos", "dos\r\n");
is_file_content ("$copath/le/lf", "unix\n");
if ($^O eq 'MSWin32') {
    is_file_content ("$copath/le/native", "native\r\n");
}
else {
    is_file_content ("$copath/le/native", "native\n");
}
