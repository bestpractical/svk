#!/usr/bin/perl -w
use Test::More tests => 4;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test('test');
my ($copath, $corpath) = get_copath ('commit');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
overwrite_file ("A/foo", "foobar\nfnord\n");
overwrite_file ("A/bar", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');
$svk->cp ('//A/foo', 'foo-cp');
$svk->cp ('//A/bar', 'bar-cp');
overwrite_file ("foo-cp", "foobar\nfnord\nnewline");
$svk->ps ('mmm', 'xxx', 'A/foo');
$svk->commit ('-m', 'cp and ps');
is_output_like ($svk, 'log', [],
		qr|r2.*cp and ps.*r1.*init|s);

is_output_like ($svk, 'log', ['-v'],
		qr|
r2.*\QChanged paths:
   M /A/foo
  A  /bar-cp (from /A/bar:1)
  M  /foo-cp (from /A/foo:1)\E.*
r1.*\Q  A  /A
  A  /A/bar
  A  /A/foo\E|s);

$svk->mirror ('/test/A', "file://$repospath/A");
$svk->sync ('/test/A');

is_output_like ($svk, 'log', ['-v', '-l1', '/test/'],
		qr'r3 \(orig r2\)');
is_output_like ($svk, 'log', ['-v', '-l1', '/test/A/'],
		qr'r3 \(orig r2\)');
