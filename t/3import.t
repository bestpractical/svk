#!/usr/bin/perl
use Test::More tests => 1;
use strict;
require 't/tree.pl';

my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('basic');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

$svk->import ('-m', 'test import', '//import', 'lib');

ok(1)
