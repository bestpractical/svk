#!/usr/bin/perl -w
use Test::More tests => 8;
use strict;
use File::Path;
require 't/tree.pl';

my ($xd, $svk) = build_test('test');
my ($copath, $corpath) = get_copath ('import');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
mkdir $copath;
overwrite_file ("$copath/filea", "foobarbazz");
overwrite_file ("$copath/fileb", "foobarbazz");
overwrite_file ("$copath/filec", "foobarbazz");
overwrite_file ("$copath/exe", "foobarbazz");
chmod (0755, "$copath/exe");
mkdir "$copath/dir";
overwrite_file ("$copath/dir/filed", "foobarbazz");

$svk->import ('-m', 'test import', '//import', $copath);

overwrite_file ("$copath/filea", "foobarbazzblah");
overwrite_file ("$copath/dir/filed", "foobarbazzbozo");

unlink "$copath/fileb";

$svk->import ('-m', 'test import', '//import', $copath);
rmtree [$copath];
$svk->checkout ('//import', $copath);

ok (-e "$copath/filea");
ok (!-e "$copath/fileb");
ok (-e "$copath/filec");
ok (-e "$copath/dir/filed");
ok (-x "$copath/exe", 'executable bit imported');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);
$svk->mkdir ('-m', 'init', '/test/A');
$svk->mirror ('//m', "file://${srepospath}".($spath eq '/' ? '' : $spath));
$svk->sync ('//m');
is_output ($svk, 'import', ['--force', '-m', 'import into mirrored path', '//m', $copath],
	   ["Import path (/m) is different from the copath (/import)"]);
rmtree [$copath];
$svk->checkout ('//m', $copath);
overwrite_file ("$copath/filea", "foobarbazz");
waste_rev ($svk, '/test/F') for 1..10;
$svk->import ('--force', '-m', 'import into mirrored path', '//m', $copath);
is ($srepos->fs->youngest_rev, 22, 'import to remote directly');

append_file ("$copath/filea", "fnord");

$svk->import ('--force', '-m', 'import into mirrored path', '//m', $copath);
is ($srepos->fs->youngest_rev, 23, 'import to remote directly with proper base rev');
