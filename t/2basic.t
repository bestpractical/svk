#!/usr/bin/perl
use Test::More tests => 10;
use strict;
require 't/tree.pl';
use SVK::Command;
$svk::info = build_test();
my ($copath, $corpath) = get_copath ('basic');
my ($repospath, undef, $repos) = svk::find_repos ('//', 1);
svk::checkout ('//', $copath);
mkdir "$copath/A";
overwrite_file ("$copath/A/foo", "foobar");
overwrite_file ("$copath/A/bar", "foobarbazz");

svk::add ("$copath/A");
overwrite_file ("$copath/A/notused", "foobarbazz");
ok(exists $svk::info->{checkout}->get
   ("$corpath/A/foo")->{'.schedule'}, 'add recursively');
ok(!exists $svk::info->{checkout}->get
   ("$corpath/A/notused")->{'.schedule'}, 'add works on specified target only');
# check output with selecting some io::stringy object?
#svk::status ("$copath");
svk::commit ('-m', 'commit message here', "$copath");
ok ($svk::info->{checkout}->get ("$corpath")->{revision} == 1,
    'checkout optimzation after commit');
mkdir "$copath/A/new";
mkdir "$copath/A/new/newer";
svk::add ("$copath/A/new");
svk::revert ('-R', "$copath/A/new");

ok(!$svk::info->{checkout}->get ("$corpath/A/new")->{'.schedule'});

ok($svk::info->{checkout}->get ("$corpath/A/foo")->{revision} == 1);
svk::update ("$copath");
ok($svk::info->{checkout}->get ("$corpath")->{revision} == 1);

svk::ps ('someprop', 'propvalue', "$copath/A");
svk::ps ('moreprop', 'propvalue', "$copath/A");
overwrite_file ("$copath/A/baz", "zzzz");
append_file ("$copath/A/foo", "foobar");
svk::add ("$copath/A/baz");
svk::ps ('someprop', 'propvalue', "$copath/A/baz");
svk::status ("$copath/A");
svk::pl ('-v', "$copath/A/baz");

svk::commit ('-m', 'commit message here', "$copath/A");
svk::rm ("$copath/A/bar");
ok(!-e "$copath/A/bar");
svk::commit ('-m', 'remove files', "$copath/A");

svk::revert ("$copath/A/bar");
ok(!-e "$copath/A/bar");

svk::revert ('-R', "$copath/A");
ok(!-e "$copath/A/bar");

svk::pl ('-v', "$copath/A/baz");

svk::status ("$copath/A");
svk::ps ('neoprop', 'propvalue', "$copath/A/baz");
svk::pl ("$copath/A/baz");
svk::pl ("$copath/A");
svk::commit ('-m', 'commit message here', "$copath/A");

svk::ps ('-m', 'set propdirectly', 'directprop' ,'propvalue', '//A');
svk::update ($copath);

ok (eq_hash (SVK::XD::do_proplist ($svk::info,
				   repos => $repos,
				   copath => $copath,
				   path => '/A',
				   rev => $repos->fs->youngest_rev,
				  ),
	     { directprop => 'propvalue',
	       someprop => 'propvalue',
	       moreprop => 'propvalue'}), 'prop matched');

