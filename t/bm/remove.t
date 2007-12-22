#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 10;
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

my ($copath, $corpath) = get_copath('basic-trunk');

$svk->checkout('//mirror/MyProject/trunk', $copath);

chdir($copath);

is_output_like ($svk, 'branch', ['--create', 'feature/foo', '--switch-to'], qr'Project branch created: feature/foo');

is_output_like ($svk, 'branch', ['--create', 'bugfix/bar', '--switch-to'], qr'Project branch created: bugfix/bar');

$svk->branch('--create', 'bugfix/foobar');
$svk->branch('--create', 'feature/barfoo');

is_output($svk, 'br', ['-l', '//mirror/MyProject'],
          ['bugfix/bar', 'bugfix/foobar', 'feature/barfoo', 'feature/foo']);

$svk->branch('--remove', 'feature/foo', 'feature/barfoo');

is_output($svk, 'br', ['-l', '//mirror/MyProject'],
          ['bugfix/bar', 'bugfix/foobar']);

$svk->branch('--remove', 'bugfix/*');

is_output($svk, 'br', ['-l', '//mirror/MyProject'], []);

$svk->branch('--create', 'foobar');
$svk->branch('--create', 'foobar2');
$svk->branch('--create', 'feature/foobar3');
$svk->branch('--create', 'bugfix/foobar4');

is_output($svk, 'br', ['-l', '//mirror/MyProject'],
          ['bugfix/foobar4', 'feature/foobar3', 'foobar', 'foobar2']);

$svk->branch('--remove', '*');

is_output($svk, 'br', ['-l', '//mirror/MyProject'], []);

#$svk->log('//mirror/MyProject');
#warn $output;
$svk->branch('--create', 'foobar5');
$svk->branch('--create', 'foobar6');
$svk->branch('--create', 'feature/foobar7');
$svk->branch('--create', 'bugfix/foobar8');

is_output($svk, 'br', ['-l', '//mirror/MyProject'],
          ['bugfix/foobar8', 'feature/foobar7', 'foobar5', 'foobar6']);

$svk->branch('--remove', 'fake', 'foobar*');

is_output($svk, 'br', ['-l', '//mirror/MyProject'],
          ['bugfix/foobar8', 'feature/foobar7']);

$svk->branch('--remove', '*');

is_output($svk, 'br', ['-l', '//mirror/MyProject'], []);

1;
