#!/usr/bin/perl -w
use strict;
use Test::More;
use File::Copy qw( copy );
BEGIN { require 't/tree.pl' };
our $output;

eval "require SVN::Mirror"
or plan skip_all => "SVN::Mirror not installed";
plan tests => 24;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test();
my ($xd2, $svk2) = build_test();

is_output_like ($svk, 'patch', [], qr'SYNOPSIS');
is_output_like ($svk, 'patch', ['blah'], qr'SYNOPSIS');
is_output ($svk, 'patch', ['view'], ['Filename required.']);

$svk->mkdir ('-m', 'init', '//trunk');
my $tree = create_basic_tree ($xd, '//trunk');
my ($repospath, $path, $repos) = $xd->find_repos ('//trunk', 1);
my ($repospath2, undef, $repos2) = $xd2->find_repos ('//trunk', 1);
my $uri = uri($repospath);
$svk2->mirror ('//trunk', $uri.($path eq '/' ? '' : $path));
$svk2->sync ('//trunk');
$svk2->copy ('-m', 'local branch', '//trunk', '//local');

my ($copath, $corpath) = get_copath ('patch');

$svk2->checkout ('//local', $copath);

append_file ("$copath/B/fe", "fnord\n");
$svk2->commit ('-m', "modified on local", $copath);

my ($uuid, $uuid2) = map {$_->fs->get_uuid} ($repos, $repos2);

is_output ($svk2, 'patch', ['create', 'test-1', '//local', '//trunk'],
	   ['U   B/fe',
	    'Patch test-1 created.']);

my $log1 = ['Log:',
	    ' ----------------------------------------------------------------------',
	    qr'.*',
	    ' local branch',
	    ' ----------------------------------------------------------------------',
	    qr'.*',
	    ' modified on local',
	    ' ----------------------------------------------------------------------'];
my $patch1 = ['',
	      '=== B/fe',
	      '==================================================================',
	      '--- B/fe  (revision 3)',
	      '+++ B/fe  (patch test-1 level 1)',
	      '@@ -1 +1,2 @@',
	      ' file fe added later',
	      '+fnord'];

is_output ($svk2, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 1',
	    "Source: $uuid2:/local:6 [local]",
	    "Target: $uuid:/trunk:3 [mirrored]",
	    @$log1, @$patch1]);

ok (-e "$xd2->{svkpath}/patch/test-1.svkpatch");
mkdir ("$xd->{svkpath}/patch");
copy ("$xd2->{svkpath}/patch/test-1.svkpatch" => "$xd->{svkpath}/patch/test-1.svkpatch");
is_output ($svk, 'patch', ['list'], ['test-1@1: ']);

my ($scopath, $scorpath) = get_copath ('patch1');
$svk->checkout ('//trunk', $scopath);
overwrite_file ("$scopath/B/fe", "on trunk\nfile fe added later\n");
$svk->commit ('-m', "modified on trunk", $scopath);

$svk->patch ('view', 'test-1');
is_output ($svk, 'patch', [qw/test test-1/], ['G   B/fe', 'Empty merge.'],
	   'patch still applicable from server.');

is_output ($svk, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 1',
	    "Source: $uuid2:/local:6",
	    "Target: $uuid:/trunk:3 [local] [updated]",
	    @$log1, @$patch1]);

$svk2->sync ('-a');

is_output ($svk2, 'patch', [qw/test test-1/],
	   ["Merging back to SVN::Mirror source $uri/trunk.",
	    'Checking against mirrored directory locally.',
	    'G   B/fe',
	    'Empty merge.'],
	   'patch still applicable from original.');

is_output ($svk2, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 1',
	    "Source: $uuid2:/local:6 [local]",
	    "Target: $uuid:/trunk:3 [mirrored] [updated]",
	    @$log1, @$patch1]);

is_output ($svk2, 'patch', ['update', 'test-1'],
	   ['G   B/fe']);

my $patch2 = [split ("\n", << 'END_OF_DIFF')];

=== B/fe
==================================================================
--- B/fe  (revision 4)
+++ B/fe  (patch test-1 level 1)
@@ -1,2 +1,3 @@
 on trunk
 file fe added later
+fnord

END_OF_DIFF

is_output ($svk2, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 1',
	    "Source: $uuid2:/local:6 [local]",
	    "Target: $uuid:/trunk:4 [mirrored]",
	    @$log1, @$patch2]);

copy ("$xd2->{svkpath}/patch/test-1.svkpatch" => "$xd->{svkpath}/patch/test-1.svkpatch");

is_output ($svk, 'patch', [qw/test test-1/], ['U   B/fe', 'Empty merge.'],
	   'patch applies cleanly on server.');

is_output ($svk2, 'patch', [qw/test test-1/],
	   ["Merging back to SVN::Mirror source $uri/trunk.",
	    'Checking against mirrored directory locally.',
	    'U   B/fe',
	    'Empty merge.'],
	   'patch applies cleanly from local.');

is_output ($svk, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 1',
	    "Source: $uuid2:/local:6",
	    "Target: $uuid:/trunk:4 [local]",
	    @$log1, @$patch2]);

overwrite_file ("$scopath/B/fe", "on trunk\nfile fe added later\nbzzzzz\n");
$svk->commit ('-m', "modified on trunk", $scopath);

is_output ($svk, 'patch', [qw/test test-1/],
	   ['C   B/fe', 'Empty merge.', '1 conflict found.',
	    'Please do a merge to resolve conflicts and regen the patch.'],
	   'patch not applicable due to conflicts.');
overwrite_file ("$copath/B/fe", "file fe added later\nbzzzzz\nfnord\n");
$svk2->commit ('-m', "catch up on local", $copath);
is_output ($svk2, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 1',
	    "Source: $uuid2:/local:6 [local] [updated]",
	    "Target: $uuid:/trunk:4 [mirrored]",
	    @$log1, @$patch2]);
is_output ($svk2, 'patch', [qw/regen test-1/],
	   ['G   B/fe']);

is_output ($svk2, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 2',
	    "Source: $uuid2:/local:8 [local]",
	    "Target: $uuid:/trunk:4 [mirrored]",
	    @$log1,
	    qr'.*',
	    ' catch up on local',
	    ' ----------------------------------------------------------------------',
	    '',
	    '=== B/fe',
	    '==================================================================',
	    '--- B/fe  (revision 4)',
	    '+++ B/fe  (patch test-1 level 2)',
	    '@@ -1,2 +1,4 @@',
	    ' on trunk',
	    ' file fe added later',
	    '+bzzzzz',
	    '+fnord']);

$svk2->sync ('-a');
is_output ($svk2, 'patch', ['view', 'test-1'],
	   ['=== Patch <test-1> level 2',
	    "Source: $uuid2:/local:8 [local]",
	    "Target: $uuid:/trunk:4 [mirrored] [updated]",
	    @$log1,
	    qr'.*',
	    ' catch up on local',
	    ' ----------------------------------------------------------------------',
	    '',
	    '=== B/fe',
	    '==================================================================',
	    '--- B/fe  (revision 4)',
	    '+++ B/fe  (patch test-1 level 2)',
	    '@@ -1,2 +1,4 @@',
	    ' on trunk',
	    ' file fe added later',
	    '+bzzzzz',
	    '+fnord']);
TODO: {
local $TODO = 'later';

is_output ($svk2, 'patch', ['update', 'test-1'],
	   ['G   B/fe']);
is_output ($svk, 'patch', [qw/test test-1/], ['U   B/fe', 'Empty merge.']);
is_output ($svk2, 'patch', [qw/test test-1/], ['U   B/fe', 'Empty merge.']);
}
