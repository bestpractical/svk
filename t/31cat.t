#!/usr/bin/perl -w
use Test::More tests => 5;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('cat');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
is_output_like ($svk, 'cat', [], qr'SYNOPSIS', 'cat - help');

chdir ($copath);
mkdir ('A');
overwrite_file ("A/foo", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');
append_file ('A/foo', "barbar\n");
$svk->ps ('svn:keywords', 'FileRev', 'A/foo');
$svk->commit ('-m', 'modify');

is_output ($svk, 'cat', ['A/foo'], [qw/foobar barbar/]);
is_output ($svk, 'cat', ['//A/foo'], [qw/foobar barbar/]);
is_output ($svk, 'cat', ['-r1', 'A/foo'], ['foobar']);
is_output ($svk, 'cat', ['-r1', '//A/foo'], ['foobar']);
