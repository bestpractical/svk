#!/usr/bin/perl -w
use strict;
use Test::More tests => 7;
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

my ($copath, $corpath) = get_copath ('proj_co');

mkdir($copath);
mkdir($copath."/A");

$svk->br('--create', 'feature/foo', '//mirror/MyProject');

is_output ($svk, 'branch', ['--list', '//mirror/MyProject'],
    ['feature/foo']);

is_output ($svk, 'branch', ['--checkout', 'feature/foo'],
    [qr/path \S+ is not a checkout path./]);

chdir($copath."/A");
is_output_like ($svk, 'branch', ['--checkout', 'feature/foo', '//mirror/MyProject'],
    qr'Syncing \S+ in \S+A/feature/foo to \d.+');

is_output_like ($svk, 'branch', ['--checkout', 'feature/foo', '//mirror/MyProject', '../B/'],
    qr'Syncing \S+ in \S+B to \d.+');

chdir('../B');

is_output_like ($svk, 'info',[],
    qr'Depot Path: //mirror/MyProject/branches/feature/foo');

# swap the order, and co the trunk
is_output_like ($svk, 'branch', ['--checkout', 'trunk', '../C', '//mirror/MyProject'],
    qr'Syncing \S+ in \S+C to \d.+');

chdir('../C');

is_output_like ($svk, 'info',[],
    qr'Depot Path: //mirror/MyProject/trunk');
