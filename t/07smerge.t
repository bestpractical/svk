#!/usr/bin/perl -w
use strict;
require 't/tree.pl';
use Test::More;
our $output;
eval "require SVN::Mirror"
or plan skip_all => "SVN::Mirror not installed";
plan tests => 15;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test', 'client2');

my $tree = create_basic_tree ($xd, '/test/');
my $pool = SVN::Pool->new_default;

my ($copath, $corpath) = get_copath ('smerge');
my ($scopath, $scorpath) = get_copath ('smerge-source');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my ($nrepospath, undef, $nrepos) = $xd->find_repos ('/client2/', 1);

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

my ($suuid, $srev) = ($srepos->fs->get_uuid, $srepos->fs->youngest_rev);

TODO: {
local $TODO = 'better target checks';

is_output ($svk, 'smerge', ['-C', '//m/be', '//l/be'],
	   ["Can't merge file yet."]);

is_output ($svk, 'smerge', ['-C', '//m/be', '//l/'],
	   ["Can't merge different types of nodes"]);

}

$svk->smerge ('-C', '//m/Q', '//l/');
ok ($@ =~ m/find merge base/);

is_output ($svk, 'smerge', ['-C', '//m', '//l'],
	   ['Auto-merging (3, 6) /m to /l (base /m:3).',
	    'U   be',
	    'New merge ticket: '.$suuid.':/A:3'], 'check merge down');

my ($uuid, $rev) = ($repos->fs->get_uuid, $repos->fs->youngest_rev);
is_output ($svk, 'smerge', ['-C', '//l', '//m'],
	   ['Auto-merging (3, 5) /l to /m (base /m:3).',
	    "Merging back to SVN::Mirror source file://$srepospath/A.",
	    'Checking against mirrored directory locally.',
	    'U   Q/qu',
	    "New merge ticket: $uuid:/l:5"], 'check merge up');

is_output ($svk, 'smerge', ['-C', '//l', '//m/'],
	   ['Auto-merging (3, 5) /l to /m (base /m:3).',
	    "Merging back to SVN::Mirror source file://$srepospath/A.",
	    'Checking against mirrored directory locally.',
	    'U   Q/qu',
	    "New merge ticket: $uuid:/l:5"], 'check merge up');

$svk->merge ('-a', '-m', 'simple smerge from source', '//m', '//l');
$srev = $srepos->fs->youngest_rev;
$svk->update ($copath);
is_deeply ($xd->do_proplist (SVK::Target->new
			     ( repos => $repos,
			       copath => $corpath,
			       path => '/l',
			       revision => $repos->fs->youngest_rev,
			     )),
	   {'svk:merge' => "$suuid:/A:$srev",
	    'svm:source' => 'file://'.$srepos->path.'!/A',
	    'svm:uuid' => $suuid }, 'simple smerge from source');
$rev = $repos->fs->youngest_rev;

is_output ($svk, 'smerge', ['-m', 'simple smerge from local', '//l', '//m'],
	   ['Auto-merging (6, 7) /l to /m (base /m:6).',
	    "Merging back to SVN::Mirror source file://$srepospath/A.",
	    'U   Q/qu',
	    "New merge ticket: $uuid:/l:7",
	    'Merge back committed as revision 4.',
	    "Syncing file://$srepospath/A",
	    'Retrieving log information from 4 to 4',
	    'Committed revision 8 from revision 4.'], 'merge up');
$svk->sync ('//m');

is_deeply ($xd->do_proplist (SVK::Target->new
			     ( repos => $repos,
			       path => '/m',
			       revision => $repos->fs->youngest_rev,
			     )),
	   {'svk:merge' => "$uuid:/l:$rev",
	    'svm:source' => 'file://'.$srepos->path.'!/A',
	    'svm:uuid' => $suuid },
	   'simple smerge back to source');

$svk->smerge ('-C', '//m', '//l');
is_output ($svk, 'smerge', ['-m', 'mergedown', '//m', '//l'],
	   ['Auto-merging (7, 8) /m to /l (base /l:7).',
	    'Empty merge.'], 'merge down - empty');
is_output ($svk, 'smerge', ['-m', 'mergedown', '//m', '//l'],
	   ['Auto-merging (7, 8) /m to /l (base /l:7).',
	    'Empty merge.'], 'merge up - empty');
$svk->update ($scopath);
append_file ("$scopath/A/be", "more modification on trunk\n");
mkdir "$scopath/A/newdir";
mkdir "$scopath/A/newdir2";
overwrite_file ("$scopath/A/newdir/deepnewfile", "new file added on source\n");
overwrite_file ("$scopath/A/newfile", "new file added on source\n");
overwrite_file ("$scopath/A/newfile2", "new file added on source\n");
$svk->add (map {"$scopath/A/$_"} qw/newdir newdir2 newfile newfile2/);
append_file ("$scopath/A/Q/qz", "file appened on source\n");
$svk->propset ("bzz", "newprop", "$scopath/A/Q/qz");
$svk->propset ("bzz", "newprop", "$scopath/A/Q/qu");
$svk->commit ('-m', 'commit on trunk', $scopath);
$svk->sync ('//m');

$svk->update ($copath);
overwrite_file ("$copath/newfile", "new file added on source\n");
overwrite_file ("$copath/newfile2", "new file added on source\nalso on local\n");
mkdir ("$copath/newdir");
$svk->add ("$copath/newfile", "$copath/newdir");
append_file ("$copath/be", "modification on local\n");
append_file ("$copath/Q/qu", "modified on local\n");
$svk->rm ("$copath/Q/qz");
$svk->commit ('-m', 'commit on local', $copath);
is_output ($svk, 'smerge', ['-C', '//m', '//l'],
	   ['Auto-merging (7, 9) /m to /l (base /l:7).',
	    ' U  Q/qu',
	    '    Q/qz - skipped',
	    'C   be',
	    '    newdir - skipped',
	    'g   newfile',
	    'A   newdir2',
	    'A   newfile2',
	    "New merge ticket: $suuid:/A:5",
	    'Empty merge.', '1 conflict found.'],
	   'smerge - added file collision');
$svk->smerge ('-C', '//m', $copath);
is_output ($svk, 'smerge', ['//m', $copath],
	   ['Auto-merging (7, 9) /m to /l (base /l:7).',
	    " U  $copath/Q/qu",
	    "    $copath/Q/qz - skipped",
	    "C   $copath/be",
	    "    $copath/newdir - skipped",
	    "g   $copath/newfile",
	    "A   $copath/newdir2",
	    "C   $copath/newfile2",
	    "New merge ticket: $suuid:/A:5",
	    '2 conflicts found.']);
$svk->status ($copath);
$svk->commit ('-m', 'commit with conflict state', $copath);
ok ($output =~ m/conflict/, 'forbid commit with conflict state');
$svk->revert ("$copath/be");
$svk->resolved ("$copath/be");
# XXX: newfile2 conflicted but not added
$svk->status ($copath);
$svk->commit ('-m', 'merge down committed from checkout', $copath);
$svk->proplist ('-v', $copath);
rmdir "$copath/newdir";
$svk->revert ('-R', $copath);
ok (-e "$copath/newdir", 'smerge to checkout - add directory');
$svk->mirror ('/client2/trunk', "file://${srepospath}".($spath eq '/' ? '' : $spath));

$svk->sync ('/client2/trunk');
$svk->copy ('-m', 'client2 branch', '/client2/trunk', '/client2/local');


$svk->copy ('-m', 'branch on source', '/test/A', '/test/A-cp');
$svk->ps ('-m', 'prop on A-cp', 'blah', 'tobemerged', '/test/A');
$svk->mirror ('//m-all', "file://${srepospath}/");
$svk->sync ('//m-all');
$svk->smerge ('-C', '//m-all/A', '//m-all/A-cp');
$svk->smerge ('-m', 'merge down', '//m-all/A', '//m-all/A-cp');
$svk->pl ('-v', '//');
