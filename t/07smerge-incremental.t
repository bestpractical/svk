#!/usr/bin/perl
use strict;
require 't/tree.pl';
use Test::More;
our $output;
eval "require SVN::Mirror"
or Test::More->import (skip_all => "SVN::Mirror not installed");
Test::More->import ('tests', 2);

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');

my $tree = create_basic_tree ($xd, '/test/');
my $pool = SVN::Pool->new_default;

my ($copath, $corpath) = get_copath ('smerge-incremental');
my ($scopath, $scorpath) = get_copath ('smerge-incremental-source');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

$svk->mirror ('//m', "file://${srepospath}".($spath eq '/' ? '' : $spath));
$svk->sync ('//m');
$svk->copy ('-m', 'branch', '//m', '//l');

$svk->checkout ('//l', $copath);
append_file ("$copath/Q/qu", "modified on local branch\n");
$svk->commit ('-m', 'commit on local branch', $copath);
$svk->checkout ('//l', $copath);
append_file ("$copath/Q/qu", "modified on local branch\n");
append_file ("$copath/Q/qz", "modified on local branch\n");
$svk->commit ('-m', 'commit on local branch', $copath);

is_output ($svk, 'smerge', ['-CI', '//l', '//m'],
	   ['Auto-merging (3, 6) /l to /m (base /m:3).',
	    'Incremental merge not guaranteed even if check is successful',
	    "Merging back to SVN::Mirror source file://$srepospath/A.",
	    'Checking against mirrored directory locally.',
	    'U   Q/qu',
	    'U   Q/qz',
	    'New merge ticket: '.$repos->fs->get_uuid.':/l:6']);

is_output ($svk, 'smerge', ['-I', '//l', '//m'],
	   ['Auto-merging (3, 6) /l to /m (base /m:3).',
	    '===> Auto-merging (3, 4) /l to /m (base /m:3).',
	    "Merging back to SVN::Mirror source file://$srepospath/A.",
	    "Empty merge.",
	    '===> Auto-merging (3, 5) /l to /m (base /m:3).',
	    "Merging back to SVN::Mirror source file://$srepospath/A.",
	    'U   Q/qu',
	    'New merge ticket: '.$repos->fs->get_uuid.':/l:5',
	    'Merge back committed as revision 3.',
	    "Syncing file://$srepospath/A",
	    'Retrieving log information from 3 to 3',
	    'Committed revision 7 from revision 3.',
	    '===> Auto-merging (5, 6) /l to /m (base /l:5).',
	    "Merging back to SVN::Mirror source file://$srepospath/A.",
	    'U   Q/qu',
	    'U   Q/qz',
	    'New merge ticket: '.$repos->fs->get_uuid.':/l:6',
	    'Merge back committed as revision 4.',
	    "Syncing file://$srepospath/A",
	    'Retrieving log information from 4 to 4',
	    'Committed revision 8 from revision 4.']);
