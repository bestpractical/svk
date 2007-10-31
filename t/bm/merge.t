#!/usr/bin/perl -w
use strict;
use Test::More tests => 12;
use SVK::Test;
use File::Path;

#sub copath { SVK::Path::Checkout->copath($copath, @_) }

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

is_output_like ($svk, 'branch', ['--create', 'feature/foo','--switch-to'], qr'Project branch created: feature/foo');
overwrite_file ('A/be', "\nsome more foobar\nzz\n");
$svk->propset ('someprop', 'propvalue', 'A/be');
$svk->diff();
$svk->commit ('-m', 'commit message here (r8)','');

my $branch_foo = '/mirror/MyProject/branches/feature/foo';
my $branch_bar = '/mirror/MyProject/branches/feature/bar';
my $trunk = '/mirror/MyProject/trunk';

is_output ($svk, 'smerge',
    ['-C', '//mirror/MyProject/branches/feature/foo', '//mirror/MyProject/trunk'], 
    ["Auto-merging (0, 8) $branch_foo to $trunk (base $trunk:6).",
     "Checking locally against mirror source $uri.", 'UU  A/be',
     qr'New merge ticket: [\w\d-]+:/branches/feature/foo:7']);
is_output ($svk, 'branch', ['--merge', '-C', 'feature/foo', 'trunk'], 
    ["Auto-merging (0, 8) $branch_foo to $trunk (base $trunk:6).",
     "Checking locally against mirror source $uri.", 'UU  A/be',
     qr'New merge ticket: [\w\d-]+:/branches/feature/foo:7']);

# another branch
is_output_like ($svk, 'branch', ['--create', 'feature/bar','--switch-to'], qr'Project branch created: feature/bar');
overwrite_file ('A/Q/qu', "\nonly a bar\nzz\n");
$svk->diff();
$svk->commit ('-m', 'commit message here (r10)','');
is_output ($svk, 'branch', ['--merge', '-C', 'feature/bar', 'trunk'], 
    ["Auto-merging (0, 10) $branch_bar to $trunk (base $trunk:6).",
     "Checking locally against mirror source $uri.", 'U   A/Q/qu',
     qr'New merge ticket: [\w\d-]+:/branches/feature/bar:9']);

is_output ($svk, 'branch', ['--merge', '-C', 'feature/foo', 'trunk'], 
    ["Auto-merging (0, 8) $branch_foo to $trunk (base $trunk:6).",
     "Checking locally against mirror source $uri.", 'UU  A/be',
     qr'New merge ticket: [\w\d-]+:/branches/feature/foo:7']);

is_output ($svk, 'branch', ['--merge', '-C', 'feature/bar', 'feature/foo', 'trunk'], 
    ["Auto-merging (0, 10) $branch_bar to $trunk (base $trunk:6).",
     "Checking locally against mirror source $uri.", 'U   A/Q/qu',
     qr'New merge ticket: [\w\d-]+:/branches/feature/bar:9',
     "Auto-merging (0, 8) $branch_foo to $trunk (base $trunk:6).",
     "Checking locally against mirror source $uri.", 'UU  A/be',
     qr'New merge ticket: [\w\d-]+:/branches/feature/foo:7']);

is_output_like ($svk, 'branch', ['--merge', 'feature/bar', 'feature/foo', 'trunk'], 
    qr/Committed revision 12 from revision 11./);

$svk->switch ('//mirror/MyProject/trunk');
is_file_content ('A/Q/qu', "\nonly a bar\nzz\n", 'is the file actually merge?');
is_file_content ('A/be', "\nsome more foobar\nzz\n", 'is the file actually merge?');

is_output_like ($svk, 'info', [],
    qr/Merged From: $branch_foo, Rev. 8/, 'Merged from feature/foo at rev. 8');
is_output_like ($svk, 'info', [],
    qr/Merged From: $branch_bar, Rev. 10/, 'Merged from feature/bar at rev. 10');
