#!/usr/bin/perl
use Test::More qw(no_plan);
use strict;
use SVN::XD;
require 't/tree.pl';
package svk;
require 'bin/svk';

package main;

#compare();

$svk::info = build_test();
my $copath = 't/checkout/basic';
my $corpath = File::Spec->rel2abs($copath);
`rm -rf $copath` if -e $copath;

#$copath = File::Spec->rel2abs ($copath);
svk::checkout ('//', $copath);
mkdir "$copath/A";
open my ($fh), '>', "$copath/A/foo";
print $fh "foobar";
close $fh;
open $fh, '>', "$copath/A/bar";
print $fh "foobarbazz";
close $fh;
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

svk::rm ("$copath/A");
ok(!-e "$copath/A");
svk::commit ('-m', 'commit message here', "$copath");

use YAML;
warn Dump ($svk::info);

cleanup_test($svk::info)
