#!/usr/bin/perl -w
use strict;
use Test::More tests => 6;
use SVK::Test;
use File::Path;

my ($xd, $svk) = build_test('test');
our $output;
$svk->mkdir(-m => 'trunk', '/test/trunk');
$svk->mkdir(-m => 'trunk', '/test/branches');
$svk->mkdir(-m => 'trunk', '/test/tags');
my $tree = create_basic_tree($xd, '/test/trunk');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

$svk->mirror('//mirror/MyProject', $uri);
$svk->sync('//mirror/MyProject');

my ($copath, $corpath) = get_copath ('MyProject');
$svk->checkout('//mirror/MyProject/trunk',$copath);
chdir($copath);

is_output_like ($svk, 'branch', ['--create', 'feature/foo'], qr'Project branch created: feature/foo');
is_output_like ($svk, 'branch', ['--list'], qr'feature/foo');
$svk->br('--move', 'feature/foo', 'release-ready/bar');
is_output_like ($svk, 'branch', ['--list'], qr'release-ready/bar');
$svk->br('--move', 'release-ready/bar', 'feature/');
is_output_like ($svk, 'branch', ['--list'], qr'feature/bar');
is_output_like ($svk, 'branch', ['--create', 'feature/moo'], qr'Project branch created: feature/moo');
$svk->br('--move', 'feature/moo', 'feature/mar');
is_output_unlike ($svk, 'branch', ['--list'], qr'feature/moo');
