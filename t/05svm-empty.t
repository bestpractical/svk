#!/usr/bin/perl -w
use strict;
require 't/tree.pl';
use Test::More;
our $output;
eval "require SVN::Mirror"
or plan skip_all => "SVN::Mirror not installed";

plan tests => 2;

# build another tree to which we want to mirror ourselves.
my ($xd, $svk) = build_test('svm-empty');
$svk->mkdir ('-m', 'remote trunk', '/svm-empty/trunk');
$svk->ps ('-m', 'foo', 'bar' => 'baz', '/svm-empty/trunk');
$svk->mkdir ('-m', 'this is the local tree', '//local');
waste_rev ($svk, '//local/tree');

my ($drepospath, $dpath, $drepos) = $xd->find_repos ('/svm-empty/trunk', 1);
my $uri = uri($drepospath);
$svk->mirror ('//remote', $uri.($dpath eq '/' ? '' : $dpath));

$svk->sync ('//remote');
my ($srepospath, $spath, $srepos) = $xd->find_repos ('//remote', 1);
my $old_srev = $srepos->fs->youngest_rev;
$svk->sync ('//remote');
$svk->sync ('//remote');
$svk->sync ('//remote');
is ($srepos->fs->youngest_rev, $old_srev, 'sync is idempotent');

$svk->smerge ('-IB', '//local', '//remote');
$svk->smerge ('-IB', '//local', '//remote');
is ($drepos->fs->youngest_rev, 4, 'smerge -IB is idempotent');

