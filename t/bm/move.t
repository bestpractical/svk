#!/usr/bin/perl -w
use strict;
use Test::More tests => 8;
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

# create to local and move back
is_output_like ($svk, 'branch', ['--create', 'localfoo', '--local', '--switch-to'],
    qr'Project branch created: localfoo \(in local\)');

$svk->br('--move', 'feature/remotebar');
$svk->br('--switch', 'feature/remotebar');
is_output_like ($svk, 'branch', ['--list'], qr'feature/remotebar',
    'Move localfoo to remotebar, cross depot move');
