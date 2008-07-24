#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 1;
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

my ($copath, $corpath) = get_copath('bm-local-create');

$svk->cp(-m => 'local branch', '//mirror/MyProject/trunk', '//local/MyProject');

$svk->checkout('//mirror/MyProject/trunk', $copath);

chdir($copath);

TODO: {
local $TODO = 'see http://task.hm/FC2C';
is_output ($svk, 'branch', ['--create', 'foobar', '--local'],
    ['The local project path //local/MyProject is a branch.',
     'Please rename the directory and try again']);
}
