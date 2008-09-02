#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 6;
our $output;

my ($xd, $svk) = build_test('test');

$svk->mkdir(-m => 'trunk', '/test/trunk');
$svk->mkdir(-m => 'trunk', '/test/branches');
$svk->mkdir(-m => 'trunk', '/test/tags');
my $tree = create_basic_tree($xd, '/test/trunk');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

$svk->mirror('//mirror/myproj', $uri);
$svk->sync('//mirror/myproj');

my ($copath, $corpath) = get_copath('bm-online-offline-trunk');

$svk->checkout('//mirror/myproj/trunk', $copath);

chdir($copath);

$svk->br('--offline');

is_output_like ($svk, 'info', [],
   qr|Depot Path: //local/myproj/myproj-trunk|);

is_ancestor($svk, '//local/myproj/myproj-trunk', '/mirror/myproj/trunk', 6);

is_output($svk, 'br', ['-l', '--local', '//mirror/myproj'],
          ['myproj-trunk']);
append_file('A/be', "fnordorz\n");
$svk->commit(-m => '#H8QQ');

is_output($svk, 'br', ['--online', '-C'],
    ["Auto-merging (0, 8) /local/myproj/myproj-trunk to /mirror/myproj/trunk (base /mirror/myproj/trunk:6).",
     "===> Auto-merging (0, 7) /local/myproj/myproj-trunk to /mirror/myproj/trunk (base /mirror/myproj/trunk:6).",
     "Empty merge.",
     "===> Auto-merging (7, 8) /local/myproj/myproj-trunk to /mirror/myproj/trunk (base /mirror/myproj/trunk:6).",
     "U   A/be",
     qr"New merge ticket: [\w\d-]+:/local/myproj/myproj-trunk:8"]);
is_output_like ($svk, 'branch', ['--online'],
    qr|U   A/be|);

is_output_like ($svk, 'info', [],
   qr|Depot Path: //mirror/myproj/trunk|);

