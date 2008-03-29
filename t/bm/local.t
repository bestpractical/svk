#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 5;
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

is_output_like ($svk, 'branch', ['--create', 'feature/foobar', '--local'],
    qr'Project branch created: feature/foobar \(in local\)');

is_output($svk, 'br', ['-l', '--local', '//mirror/MyProject'],
          ['feature/foobar']);

# switch back
$svk->br('--switch', 'trunk');
is_output_like ($svk, 'info', [],
   qr|Depot Path: //mirror/MyProject/trunk|);

$svk->br('--switch', 'feature/foobar', '--local');
is_output_like ($svk, 'info', [],
   qr|Depot Path: //local/MyProject/feature/foobar|);

$svk->branch ('--create', 'localfoo', '--switch-to', '--local');
append_file ('B/S/Q/qu', "\nappend CBA on local branch localfoo\n");
$svk->commit ('-m', 'commit message','');

my $trunk = '/mirror/MyProject/trunk';
TODO: {
local $TODO = '--push need to be implemented';
is_output ($svk, 'branch', ['--push', '-C', 'smerge/foo', 'trunk'],
    ["Auto-merging (0, 10) /local/MyProject/localfoo to $trunk (base $trunk:12).",
     "Checking locally against mirror source $uri.", 'U   B/S/Q/qu',
     qr'New merge ticket: [\w\d-]+:/localfoo:9']);
}
