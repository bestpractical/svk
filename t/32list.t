#!/usr/bin/perl
use Test::More tests => 4;
use strict;
require 't/tree.pl';
our $output;

my ($xd, $svk) = build_test('','bob');

my ($copath) = get_copath ('listlocal');

$svk->checkout ('//', $copath);
chdir ("$copath");
mkdir ('A');
overwrite_file ("A/foo", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');
is_output ($svk, 'ls', ['//'], ['A/']);
is_output ($svk, 'ls', ['-f','//'], ['//A/']);

chdir("..");
my ($copath2) = get_copath ('listbob');
$svk->checkout ('/bob/', $copath2);
chdir ("$copath2");
mkdir ('A');
overwrite_file ("A/foo", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');
is_output ($svk, 'ls', ['/bob/'], ['A/']);
is_output ($svk, 'ls', ['-f','/bob/'], ['/bob/A/']);

