#!/usr/bin/perl -w
use strict;
use Test::More;
BEGIN { require 't/tree.pl' };
eval { require SVN::Mirror; 1 } or plan skip_all => 'require SVN::Mirror';
plan tests => 16;

use Cwd;
use File::Path;

my ($xd, $svk) = build_test('test');
our ($copath, $corpath) = get_copath ('import');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
our $output;

is_output_like ($svk, 'import', [], qr'SYNOPSIS', 'import - help');
is_output_like ($svk, 'import', ['foo','bar','baz'], qr'SYNOPSIS', 'import - help');

mkdir $copath;
overwrite_file ("$copath/filea", "foobarbazz");
overwrite_file ("$copath/fileb", "foobarbazz");
overwrite_file ("$copath/filec", "foobarbazz");
overwrite_file ("$copath/exe", "foobarbazz");
chmod (0755, "$copath/exe");
mkdir "$copath/dir";
overwrite_file ("$copath/dir/filed", "foobarbazz");

$svk->import ('-m', 'test import', $copath, '//import');
is_output_like ($svk, 'status', [$copath], qr'not a checkout path');

overwrite_file ("$copath/filea", "foobarbazzblah");
overwrite_file ("$copath/dir/filed", "foobarbazzbozo");

unlink "$copath/fileb";

$svk->import ('-m', 'test import', '//import', $copath);
unlink "$copath/filec";
$svk->import ('-t', '-m', 'import -t', '//import', $copath);
ok($xd->{modified}, 'will update svk config');
is_output ($svk, 'status', [$copath], []);
rmtree [$copath];
$svk->checkout ('//import', $copath);

ok (-e copath ('filea'));
ok (!-e copath ('fileb'));
ok (!-e copath ('filec'));
ok (-e copath ('dir/filed'));
ok (_x copath ('exe'), 'executable bit imported');

unlink (copath ('exe'));

my $oldwd = getcwd;
chdir ($copath);

is_output ($svk, 'import', ['//import'], ["Import source ($corpath) is a checkout path; use --from-checkout."]);

$svk->import ('-f', '-m', 'import -f', '//import');
is_output ($svk, 'status', [], []);

chdir ($oldwd);

rmtree ["$copath/dir"];

overwrite_file ("$copath/dir", "now file\n");
$svk->import ('-f', '-m', 'import -f', '//import', $copath);
rmtree [$copath];
$svk->checkout ('//import', $copath);
ok (-f copath ('dir'));

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);
$svk->mkdir ('-m', 'init', '/test/A');
SKIP: {
skip 'SVN::Mirror not installed', 3 unless HAS_SVN_MIRROR;
$svk->mirror ('//m', uri($srepospath.($spath eq '/' ? '' : $spath)));
$svk->sync ('//m');
is_output ($svk, 'import', ['--from-checkout', '-m', 'import into mirrored path', '//m', $copath],
	   ["Import path (/m) is different from the copath (/import)"]);
rmtree [$copath];
$svk->checkout ('//m', $copath);
overwrite_file ("$copath/filea", "foobarbazz");
waste_rev ($svk, '/test/F') for 1..10;
$svk->import ('--from-checkout', '-m', 'import into mirrored path', '//m', $copath);

is ($srepos->fs->youngest_rev, 22, 'import to remote directly');

append_file ("$copath/filea", "fnord");

$svk->import ('--from-checkout', '-m', 'import into mirrored path', '//m', $copath);

is ($srepos->fs->youngest_rev, 23, 'import to remote directly with proper base rev');
}
