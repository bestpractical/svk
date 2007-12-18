#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 3;
our $output;

my ($xd, $svk) = build_test('test');

$svk->mkdir(-m => 'trunk', '/test/trunk');
$svk->mkdir(-m => 'trunk', '/test/branches');
$svk->mkdir(-m => 'trunk', '/test/tags');
my $tree = create_basic_tree($xd, '/test/trunk');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

$svk->mirror('//mirror/MyProject', $uri);
$svk->sync('//mirror/MyProject');

$svk->cp(-m => 'branch Foo', '//mirror/MyProject/trunk', '//mirror/MyProject/branches/Foo');

my ($copath, $corpath) = get_copath('basic-trunk');

$svk->checkout('//mirror/MyProject/trunk', $copath);

chdir($copath);

my $proppath = { 'trunk' => '/trunk', 
    'branches' => '/branches',
    'tags' => '/tags',
    'hooks' => '/hooks',
};

$svk->propset('-m', "- project trunk path set", 'svk:project:GoodProject:path_trunk',
    $proppath->{trunk}, "//"); 
$svk->propset('-m', "- project branches path set", 'svk:project:GoodProject:path_branches',
    $proppath->{branches}, "//");
$svk->propset('-m', "- project tags path set", 'svk:project:GoodProject:path_tags',
    $proppath->{tags}, "//");
is_output ($svk, 'propget', ['svk:project:GoodProject:path_trunk', '//'], [$proppath->{trunk}]);

is_output ($svk, 'branch', ['--list','//mirror/MyProject'], ['Foo']);

$svk->mirror('--detach', '//mirror/MyProject');

# { TODO interactive mode
$svk->mirror('//mirror/NewProject', $uri);


# }
is_output ($svk, 'branch', ['--list','//mirror/NewProject'], ['Foo']);
