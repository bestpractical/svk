#!/usr/bin/perl
use Test::More qw(no_plan);
use strict;
use SVN::XD;
require 't/tree.pl';
package svk;
require 'bin/svk';

package main;

$svk::info = build_test();
my $copath = 't/checkout/basic';
my $corpath = File::Spec->rel2abs($copath);
`rm -rf $copath` if -e $copath;

svk::checkout ('//', $copath);
mkdir "$copath/A";
open my ($fh), '>', "$copath/A/foo";
print $fh "foobar\n";
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
open $fh, '>>', "$copath/A/foo";
print $fh "\nsome more foobar\nzz\n";
close $fh;
svk::commit ('-m', 'commit message here', "$copath");

svk::update ('-r', 1, $copath);
open $fh, '>', "$copath/A/foo";
print $fh "some local mods\nfoobar\n";
close $fh;
svk::update ($copath);
open $fh, '<', "$copath/A/foo";
local $/;
is (<$fh>, "some local mods\nfoobar\n\nsome more foobar\nzz\n", 'merge via update');
close $fh;

svk::update ('-r', 1, $copath);
open $fh, '<', "$copath/A/foo";
local $/;
is (<$fh>, "some local mods\nfoobar\n", 'merge via update - backward');
close $fh;
open $fh, '>', "$copath/A/foo";

print $fh "some local mods\nfoobar\n\nsome more foobarzz\nyy\n";
close $fh;
svk::update ($copath);
ok ($svk::info->{checkout}->get ("$corpath/A/foo")->{conflict}, 'conflict');

cleanup_test($svk::info)
