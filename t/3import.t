#!/usr/bin/perl
use Test::More tests => 1;
no warnings 'once';
use strict;
require 't/tree.pl';

$svk::info = build_test();
my ($copath, $corpath) = get_copath ('basic');
my ($repospath, undef, $repos) = svk::find_repos ('//', 1);

svk::import ('-m', 'test import', '//import', 'lib');

ok(1)
