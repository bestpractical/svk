#!/usr/bin/perl
use Test::More qw(no_plan);
use strict;
use SVN::XD;
require 't/tree.pl';
package svk;
require 'bin/svk';
package main;

$svk::info = build_test();
my ($copath, $corpath) = get_copath ('basic');
svk::checkout ('//', $copath);
mkdir "$copath/A";
overwrite_file ("$copath/A/foo", "foobar");
overwrite_file ("$copath/A/bar", "foobarbazz");

svk::add ("$copath/A");
svk::add ("$copath/A/foo");
svk::add ("$copath/A/bar");
# check output with selecting some io::stringy object?
#svk::status ("$copath");
svk::commit ('-m', 'commit message here', "$copath");

ok($svk::info->{checkout}->get ("$corpath")->{revision} == 0);
ok($svk::info->{checkout}->get ("$corpath/A/foo")->{revision} == 1);
svk::update ("$copath");
ok($svk::info->{checkout}->get ("$corpath")->{revision} == 1);

svk::ps ('someprop', 'propvalue', "$copath/A");
svk::ps ('moreprop', 'propvalue', "$copath/A");
overwrite_file ("$copath/A/baz", "zzzz");
svk::add ("$copath/A/baz");
svk::ps ('someprop', 'propvalue', "$copath/A/baz");
svk::rm ("$copath/A/bar");
ok(!-e "$copath/A/bar");
svk::status ("$copath/A");
svk::pl ("$copath/A/baz");

svk::commit ('-m', 'commit message here', "$copath/A");
svk::pl ("$copath/A/baz");
svk::pl ("$copath/A");

cleanup_test($svk::info)
