#!/usr/bin/perl -w
use strict;
require 't/tree.pl';
use Test::More;
our $output;
eval "require SVN::Mirror"
or plan skip_all => "SVN::Mirror not installed";

plan tests => 7;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test', 'new');

my $tree = create_basic_tree ($xd, '/test/');
my $pool = SVN::Pool->new_default;

my ($copath, $corpath) = get_copath ('smerge-incremental');
my ($scopath, $scorpath) = get_copath ('smerge-incremental-source');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my $uri = uri($srepospath);

$svk->mirror ('//m', $uri.($spath eq '/' ? '' : $spath));
$svk->sync ('//m');
$svk->copy ('-m', 'branch', '//m', '//l');

$svk->checkout ('//l', $copath);
append_file ("$copath/Q/qu", "modified on local branch\n");
$svk->commit ('-m', 'commit on local branch', $copath);

append_file ("$copath/Q/qu", "modified on local branch\n");
append_file ("$copath/Q/qz", "modified on local branch\n");
$svk->commit ('-m', 'commit on local branch', $copath);

$svk->switch ('//m', $copath);

my $uuid = $repos->fs->get_uuid;

is_output ($svk, 'smerge', ['-I', '//l', $copath],
	   ['Auto-merging (0, 6) /l to /m (base /m:3).',
	    '===> Auto-merging (0, 4) /l to /m (base /m:3).',
	    '===> Auto-merging (0, 5) /l to /m (base /m:3).',
	    __("U   $copath/Q/qu"),
	    "New merge ticket: $uuid:/l:5",
	    '===> Auto-merging (5, 6) /l to /m (base /l:5).',
	    __("U   $copath/Q/qu"),
	    __("U   $copath/Q/qz"),
	    "New merge ticket: $uuid:/l:6"]);

$svk->revert ('-R', $copath);

is_output ($svk, 'smerge', ['//l@5', $copath],
	   ['Auto-merging (0, 5) /l to /m (base /m:3).',
	    __("U   $copath/Q/qu"),
	    "New merge ticket: $uuid:/l:5"]);

is_output ($svk, 'smerge', ['//l', $copath],
	   ['Auto-merging (5, 6) /l to /m (base /l:5).',
	    __("U   $copath/Q/qu"),
	    __("U   $copath/Q/qz"),
	    "New merge ticket: $uuid:/l:6"], 'smerge respects ticket on copath');
$svk->revert ('-R', $copath);

$svk->switch ('//l', $copath);

is_output ($svk, 'smerge', ['-CI', '//l', '//m'],
	   ['Auto-merging (0, 6) /l to /m (base /m:3).',
	    'Incremental merge not guaranteed even if check is successful',
	    "Checking locally against mirror source $uri/A.",
	    'U   Q/qu',
	    'U   Q/qz',
	    "New merge ticket: $uuid:/l:6"]);

is_output ($svk, 'smerge', ['-I', '//l', '//m'],
	   ['Auto-merging (0, 6) /l to /m (base /m:3).',
	    '===> Auto-merging (0, 4) /l to /m (base /m:3).',
	    "Merging back to mirror source $uri/A.",
	    "Empty merge.",
	    '===> Auto-merging (0, 5) /l to /m (base /m:3).',
	    "Merging back to mirror source $uri/A.",
	    'U   Q/qu',
	    "New merge ticket: $uuid:/l:5",
	    'Merge back committed as revision 3.',
	    "Syncing $uri/A",
	    'Retrieving log information from 3 to 3',
	    'Committed revision 7 from revision 3.',
	    '===> Auto-merging (5, 6) /l to /m (base /l:5).',
	    "Merging back to mirror source $uri/A.",
	    'U   Q/qu',
	    'U   Q/qz',
	    "New merge ticket: $uuid:/l:6",
	    'Merge back committed as revision 4.',
	    "Syncing $uri/A",
	    'Retrieving log information from 4 to 4',
	    'Committed revision 8 from revision 4.']);

$svk->mkdir ('-m', 'fnord', '/new/A');

($srepospath, $spath, $srepos) = $xd->find_repos ('/new/A', 1);
$svk->mirror ('//new', uri($srepospath).($spath eq '/' ? '' : $spath));
$svk->sync ('//new');
is_output_like ($svk, 'smerge', ['-CI', '//m', '//new'],
		qr"Can't find merge base for /m and /new");
$svk->smerge ('-BCI', '//m', '//new');
$svk->smerge ('-BI', '--remoterev', '--host', 'source', '//m', '//new');
is ($srepos->fs->youngest_rev, 5);


