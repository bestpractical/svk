#!/usr/bin/perl -w
use strict;
require 't/tree.pl';
use Test::More;
our $output;
eval "require SVN::Mirror"
or plan skip_all => "SVN::Mirror not installed";
plan tests => 6;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');

my $tree = create_basic_tree ($xd, '/test/');

my ($copath, $corpath) = get_copath ('smerge-file');
my ($scopath, $scorpath) = get_copath ('smerge-file-source');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

$svk->mirror ('//m', "file://${srepospath}".($spath eq '/' ? '' : $spath));
$svk->sync ('//m');

$svk->copy ('-m', 'branch', '//m', '//l');

$svk->checkout ('/test/', $scopath);
append_file ("$scopath/A/be", "modified on trunk\n");
$svk->commit ('-m', 'commit on trunk', $scopath);
$svk->checkout ('//l', $copath);
append_file ("$copath/Q/qu", "modified on local branch\n");
$svk->commit ('-m', 'commit on local branch', $copath);

$svk->sync ('//m');

my $uuid = $repos->fs->get_uuid;
my ($suuid, $srev) = ($srepos->fs->get_uuid, $srepos->fs->youngest_rev);

is_output ($svk, 'smerge', ['-C', '//m/be', '//l/be'],
	   ['Auto-merging (2, 6) /m/be to /l/be (base /m/be:2).',
	    'U   be',
	    "New merge ticket: $suuid:/A/be:3"]);

is_output ($svk, 'smerge', ['//m/be', "$copath/be"],
	   ['Auto-merging (2, 6) /m/be to /l/be (base /m/be:2).',
	    "U   $copath/be",
	    "New merge ticket: $suuid:/A/be:3"]);

is_output ($svk, 'status', [$copath],
	   ["MM  $copath/be"]);
$svk->commit ('-m', 'commit merged file', $copath);
append_file ("$scopath/A/be", "modified on trunk\n");
$svk->commit ('-m', 'commit on trunk', $scopath);
$svk->sync ('//m');
is_output ($svk, 'smerge', ['-C', '//m/be', '//l/be'],
	   ['Auto-merging (6, 8) /m/be to /l/be (base /m/be:6).',
	    'U   be',
	    "New merge ticket: $suuid:/A/be:4"]);
$svk->cp ('-m', 'cp', '//l/be', '//l/be.cp');
$svk->update ($copath);
append_file ("$copath/be", "modified on after cp\n");
$svk->commit ('-m', 'merge file-only', $copath);
is_output ($svk, 'smerge', ['-C', '//l/be', '//l/be.cp'],
	   ['Auto-merging (7, 10) /l/be to /l/be.cp (base /l/be:7).',
	    'U   be',
	    "New merge ticket: $uuid:/l/be:10"]);
is_output ($svk, 'smerge', ['-C', '//l/be', "$copath/be.cp"],
	   ['Auto-merging (7, 10) /l/be to /l/be.cp (base /l/be:7).',
	    "U   $copath/be",
	    "New merge ticket: $uuid:/l/be:10"]);
