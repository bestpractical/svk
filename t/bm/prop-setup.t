#!/usr/bin/perl -w
# This test for trunk and/or branches are not in trunk/ and/or branches/ directories
use strict;
use SVK::Test;
plan tests => 6;
our $output;

my ($xd, $svk) = build_test('test');

my $tree = create_basic_tree($xd, '/test/');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

my ($copath, $corpath) = get_copath('prop-setup');

my $props = { 
    'svk:project:A:path-trunk' => '/A',
    'svk:project:A:path-branches' => '/A-b',
    'svk:project:A:path-tags' => '/',
};

$svk->mirror('//mirror/nomeans', $uri);
$svk->sync('//mirror/nomeans');

$svk->checkout('//mirror/nomeans',$copath);

chdir($copath);

is_output ($svk, 'branch', ['--list', '//mirror/nomeans/A'], ['No project branch found.']);
TODO: {
local $TODO = 'Need to implement br --setup ';
$answer = ['','/A-b',''];
$svk->branch('--setup', '//mirror/nomeans/A');
is_output ($svk, 'branch', ['--list', '//mirror/nomeans/A'], []);

chdir("A/");
is_output ($svk, 'branch', ['--list'], []);
is_output_like ($svk, 'branch', ['--create', 'bar'], qr'Project branch created: bar');
is_output ($svk, 'branch', ['--list'], ['bar']);
is_output ($svk, 'list', ['//mirror/nomeans/A-b/bar'],
    ['Q/' ,'be']);
}
