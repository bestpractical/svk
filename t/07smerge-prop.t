#!/usr/bin/perl -w
use strict;
use Test::More;
BEGIN { require 't/tree.pl' };
our ($output, $answer);
plan tests => 6;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test();
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;
$svk->mkdir ('-m', 'init', '//trunk');
my $tree = create_basic_tree ($xd, '//trunk');

my ($copath, $corpath) = get_copath ('smerge-prop');

$svk->cp ('-m', 'local branch', '//trunk', '//local');

$svk->ps ('-m', 'add prop on trunk', 'smerge-prop', 'new prop on trunk', '//trunk/A/be');
is_output ($svk, 'smerge', ['-C', '-t', '//local'],
	   ['Auto-merging (3, 5) /trunk to /local (base /trunk:3).',
	    ' U  A/be',
	    "New merge ticket: $uuid:/trunk:5"]);

$svk->ps ('-m', 'add prop on local', 'smerge-prop', 'new prop on trunk', '//local/A/be');
is_output ($svk, 'smerge', ['-C', '-t', '//local'],
	   ['Auto-merging (3, 5) /trunk to /local (base /trunk:3).',
	    ' g  A/be',
	    "New merge ticket: $uuid:/trunk:5"]);

# test prop merge without base
$svk->ps ('-m', 'add prop on local', 'smerge-prop', 'new prop on local', '//local/A/be');
is_output ($svk, 'smerge', ['-C', '-t', '//local'],
	   ['Auto-merging (3, 5) /trunk to /local (base /trunk:3).',
	    ' C  A/be',
	    "New merge ticket: $uuid:/trunk:5",
	    'Empty merge.',
	    '1 conflict found.']);

is_output ($svk, 'smerge', ['-m', 'merge down', '-t', '//local'],
	   ['Auto-merging (3, 5) /trunk to /local (base /trunk:3).',
	    ' C  A/be',
	    "New merge ticket: $uuid:/trunk:5",
	    'Empty merge.',
	    '1 conflict found.']);

$answer = 't';
is_output ($svk, 'smerge', ['-m', 'merge down', '-t', '//local'],
	   ['Auto-merging (3, 5) /trunk to /local (base /trunk:3).',
	    ' G  A/be',
	    "New merge ticket: $uuid:/trunk:5",
	    'Committed revision 8.']);

is_output ($svk, 'pg', ['smerge-prop', "//local/A/be"],
	   ['new prop on trunk'], 'theirs accepted');

# XXX: test prop merge with base
# XXX: test prop merge on checkout
