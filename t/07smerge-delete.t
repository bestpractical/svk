#!/usr/bin/perl
use Test::More tests => 7;
use strict;
use File::Path;
use Cwd;
require 't/tree.pl';

my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('smerge-delete');
$svk->mkdir ('-m', 'trunk', '//trunk');
$svk->checkout ('//trunk', $copath);
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;

mkdir "$copath/A";
mkdir "$copath/A/deep";
mkdir "$copath/B";
overwrite_file ("$copath/A/foo", "foobar\n");
overwrite_file ("$copath/A/deep/foo", "foobar\n");
overwrite_file ("$copath/A/bar", "foobar\n");
overwrite_file ("$copath/A/normal", "foobar\n");
overwrite_file ("$copath/test.pl", "foobarbazzz\n");
$svk->add ("$copath/test.pl", "$copath/A", "$copath/B");
$svk->commit ('-m', 'init', "$copath");

$svk->cp ('-m', 'branch', '//trunk', '//local');

$svk->rm ('-m', 'rm A on trunk', '//trunk/A');
$svk->rm ('-m', 'rm B on trunk', '//trunk/B');
append_file ("$copath/A/foo", "modified\n");
overwrite_file ("$copath/A/unused", "foobar\n");
my $oldwd = getcwd;
chdir ($copath);
is_output ($svk, 'up', [],
	   ["Syncing //trunk(/trunk) in $corpath to 5.",
	    'C   A',
	    'D   A/bar',
	    'D   A/deep',
	    'C   A/foo',
	    'D   A/normal',
	    'D   B',
	    'Empty merge.',
	    '2 conflicts found.'
	   ], 'delete entry but modified on checkout');
chdir ($oldwd);
ok (-e "$copath/A/foo", 'local file not deleted');
ok (!-e "$copath/B/foo", 'unmodified dir deleted');
rmtree (["$copath/A"]);
$svk->switch ('//local', $copath);
append_file ("$copath/A/foo", "modified\n");
overwrite_file ("$copath/A/unused", "foobar\n");
is_output ($svk, 'smerge', ['//trunk', $copath],
	   ['Auto-merging (2, 5) /trunk to /local (base /trunk:2).',
	    'C   A',
	    'D   A/bar',
	    'D   A/deep',
	    'C   A/foo',
	    'D   A/normal',
	    'D   B',
	    'Empty merge.',
	    '2 conflicts found.'
	   ]);
ok (-e "$copath/A/foo", 'local file not deleted');
ok (!-e "$copath/B/foo", 'unmodified dir deleted');
$svk->revert ('-R', $copath);

append_file ("$copath/A/foo", "modified\n");
overwrite_file ("$copath/A/unused", "foobar\n");
$svk->add ("$copath/A/unused");
$svk->rm ("$copath/A/bar");
$svk->commit ('-m', 'local modification', $copath);
is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
	   ['Auto-merging (2, 6) /trunk to /local (base /trunk:2).',
	    'C   A',
	    'd   A/bar',
	    'D   A/deep',
	    'C   A/foo',
	    'D   A/normal',
	    'D   B',
	    'Empty merge.',
	    '2 conflicts found.']);

