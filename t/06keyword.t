#!/usr/bin/perl -w
use strict;
use Test::More tests => 17;
BEGIN { require 't/tree.pl' };

my ($xd, $svk) = build_test();

my $tree = create_basic_tree ($xd, '//');
my ($copath, $corpath) = get_copath ('keyword');
our $output;
$svk->checkout ('//', $copath);

is_file_content ("$copath/A/be",
		 "\$Rev: 1 \$ \$Revision: 1 \$\n\$FileRev: #1 \$\nfirst line in be\n2nd line in be\n",
		 'basic Id');
append_file ("$copath/A/be", "some more\n");
$svk->ps ('svn:executable', 'on', "$copath/A/be");
ok (_x "$copath/A/be", 'svn:excutable effective after ps');
$svk->commit ('-m', 'some modifications', $copath);
ok (_x "$copath/A/be", 'take care of svn:executable after commit');

my $newcontent = "\$Rev: 3 \$ \$Revision: 3 \$\n\$FileRev: #2 \$\nfirst line in be\n2nd line in be\nsome more\n";

is_file_content ("$copath/A/be", $newcontent, 'commit Id');

append_file ("$copath/A/be", "some more\n");
$svk->revert ("$copath/A/be");
is_file_content ("$copath/A/be", $newcontent, 'commit Id');

ok (_x "$copath/A/be", 'take care of svn:executable after revert');
append_file ("$copath/A/be", "some more\n");
$svk->commit ('-m', 'some more modifications', $copath);

is_file_content ("$copath/A/be",
		 "\$Rev: 4 \$ \$Revision: 4 \$\n\$FileRev: #3 \$\nfirst line in be\n2nd line in be\nsome more\nsome more\n");
$svk->update ('-r', 3, $copath);
ok (_x "$copath/A/be", 'take care of svn:executable after update');
is_file_content ("$copath/A/be", $newcontent, 'commit Id');

my $cofile = __"$copath/A/be";
is_output_like ($svk, 'update', ['-r', 2, $copath], qr|^UU  \Q$cofile\E$|m,
		'keyword does not cause merge');

ok (not_x "$copath/A/be", 'take care of removing svn:executable after update');
overwrite_file ("$copath/A/foo", "\$Rev: 999 \$");
$svk->add ("$copath/A/foo");
$svk->commit ('-m', 'adding a file', $copath);

is_file_content ("$copath/A/foo", "\$Rev: 999 \$", 'commit unreverted ref');
append_file ("$copath/A/foo", "some more\n");
$svk->ps ('svn:keywords', 'URL Author Rev Date Id FileRev', "$copath/A/foo");
$svk->commit ('-m', 'appending a file and change props', $copath);
is_output ($svk, 'st', ["$copath/A/foo"], [], 'commit does keyword expansion');

mkdir ("$copath/le");
overwrite_file_raw ("$copath/le/dos", "dos\n");
overwrite_file_raw ("$copath/le/unix", "unix\n");
overwrite_file_raw ("$copath/le/native", "native\n");
overwrite_file_raw ("$copath/le/na", "na\n");
$svk->add ("$copath/le");
$svk->ps ('svn:eol-style', 'CRLF', "$copath/le/dos");
$svk->ps ('svn:eol-style', 'native', "$copath/le/native");
$svk->ps ('svn:eol-style', 'LF', "$copath/le/unix");
$svk->ps ('svn:eol-style', 'NA', "$copath/le/na");
$svk->commit ('-m', 'test line ending', $copath);
is_file_content_raw ("$copath/le/dos", "dos\r\n");
is_file_content_raw ("$copath/le/unix", "unix\n");
is_file_content_raw ("$copath/le/na", "na\n");
if ($^O eq 'MSWin32') {
    is_file_content_raw ("$copath/le/native", "native\r\n");
}
else {
    is_file_content_raw ("$copath/le/native", "native\n");
}
