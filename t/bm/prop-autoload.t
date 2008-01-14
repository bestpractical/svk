#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 4;
our $output;

my ($xd, $svk) = build_test('test');

$svk->mkdir(-m => 'trunk', '/test/trunk');
$svk->mkdir(-m => 'trunk', '/test/branches');
$svk->mkdir(-m => 'trunk', '/test/tags');
my $tree = create_basic_tree($xd, '/test/trunk');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

my ($copath, $corpath) = get_copath('basic-trunk');

my $props = { 
    'svk:project:projectA:path-trunk' => '/projectA/trunk',
    'svk:project:projectA:path-branches' => '/projectA/branches',
    'svk:project:projectA:path-tags' => '/projectA/tags',
};

add_prop_to_basic_tree($xd, '/test/',$props);
$svk->mirror('//mirror/MyProject', $uri);
$svk->sync('//mirror/MyProject');

is_output ($svk, 'propget',
    ['svk:project:projectA:path-trunk', '//mirror/MyProject'],
    [$props->{'svk:project:projectA:path-trunk'}]);

$svk->cp(-m => 'branch Foo', '//mirror/MyProject/trunk', '//mirror/MyProject/branches/Foo');

$svk->mirror('--detach', '//mirror/MyProject');

$answer = ['','','y','1', ''];
$svk->checkout($uri,$copath);

chdir($copath);
is_output ($svk, 'propget',
    ['svk:project:projectA:path-trunk', '//mirror/projectA'],
    [$props->{'svk:project:projectA:path-trunk'}]);

is_output ($svk, 'branch', ['--list','//mirror/projectA'], ['Foo']);
is_output ($svk, 'branch', ['--list'], ['Foo']);
