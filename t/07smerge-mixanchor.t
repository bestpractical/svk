#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl' };
plan_svm tests => 3;

our $output;
# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test', 'client2');

$svk->mkdir ('-m', 'init', '/test/trunk');
my $tree = create_basic_tree ($xd, '/test/trunk');
$svk->copy ('-m', 'branch', '/test/trunk', '/test/3.3-TESTING');

$svk->mkdir ('-m', 'something under 3.3', '/test/3.3-TESTING/newdir');
$svk->smerge ('-m', 'merge back', '-f', '/test/3.3-TESTING');

$svk->mkdir ('-m', 'something under 3.3', '/test/3.3-TESTING/3.3-only');
my ($copath, $corpath) = get_copath ('smerge-mixanchor');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/', 1);
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;
my $uri = uri($srepospath);

$svk->mirror ('//mirror', $uri.($spath eq '/' ? '' : $spath));
$svk->sync ('//mirror');

$svk->copy ('-m', 'branch', '//mirror', '//local');
$svk->copy ('-m', 'branch 3.3-TESTING', '//local/3.3-TESTING', '//3.3-exp');

$svk->mkdir ('-m', 'something under local 3.3', '//3.3-exp/local-3.3-only');
$svk->copy ('-m', 'branch 3.3-TESTING', '//3.3-exp', '//3.3-another');
$svk->mkdir ('-m', 'something under local 3.3', '//3.3-another/local-3.3-only/yay');

$svk->smerge ('-m', 'merge back 3.3-exp to local', '-f', '//3.3-exp');

is_output ($svk, 'smerge', ['-m', 'merge back local to remote', '-f', '//local'],
	   ['Auto-merging (0, 14) /local to /mirror (base /mirror:8).',
	    "Merging back to mirror source $uri.",
	    'A   3.3-TESTING/local-3.3-only',
	    ' G  3.3-TESTING',
	    "New merge ticket: $uuid:/local:14",
	    'Merge back committed as revision 8.',
	    "Syncing $uri",
	    'Retrieving log information from 8 to 8',
	    'Committed revision 15 from revision 8.']);

is_output ($svk, 'pg', ['svk:merge', '//local/3.3-TESTING', '//mirror/3.3-TESTING'],
	   ["//local/3.3-TESTING - $uuid:/3.3-exp:11",
	    "//mirror/3.3-TESTING - $uuid:/3.3-exp:11"]);

is_output ($svk, 'smerge', ['-m', 'merge back 3.3-another to remote directly', '//3.3-another', '//mirror/3.3-TESTING'],
	   ['Auto-merging (0, 13) /3.3-another to /mirror/3.3-TESTING (base /3.3-exp:11).',
	    "Merging back to mirror source $uri.",
	    'A   local-3.3-only/yay',
	    "New merge ticket: $uuid:/3.3-another:13",
	    'Merge back committed as revision 9.',
	    "Syncing $uri",
	    'Retrieving log information from 9 to 9',
	    'Committed revision 16 from revision 9.']);
