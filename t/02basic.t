#!/usr/bin/perl -w
use Test::More tests => 12;
use strict;
require 't/tree.pl';

my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('basic');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
mkdir "$copath/A";
overwrite_file ("$copath/A/foo", "foobar");
overwrite_file ("$copath/A/bar", "foobarbazz");

$svk->add ("$copath/A");
overwrite_file ("$copath/A/notused", "foobarbazz");
ok(exists $xd->{checkout}->get
   ("$corpath/A/foo")->{'.schedule'}, 'add recursively');
ok(!exists $xd->{checkout}->get
   ("$corpath/A/notused")->{'.schedule'}, 'add works on specified target only');
$svk->commit ('-m', 'commit message here', "$copath");
unlink ("$copath/A/notused");
$svk->revert ('-R', $copath);
ok(!-e "$copath/A/notused", 'non-targets not committed');
is ($xd->{checkout}->get ("$corpath")->{revision}, 1,
    'checkout optimzation after commit');
mkdir "$copath/A/new";
mkdir "$copath/A/new/newer";
$svk->add ("$copath/A/new");
$svk->revert ('-R', "$copath/A/new");

ok(!$xd->{checkout}->get ("$corpath/A/new")->{'.schedule'});

ok($xd->{checkout}->get ("$corpath/A/foo")->{revision} == 1);
$svk->update ("$copath");
ok($xd->{checkout}->get ("$corpath")->{revision} == 1);

$svk->ps ('someprop', 'propvalue', "$copath/A");
$svk->ps ('moreprop', 'propvalue', "$copath/A");
overwrite_file ("$copath/A/baz", "zzzz");
append_file ("$copath/A/foo", "foobar");
$svk->add ("$copath/A/baz");
$svk->ps ('someprop', 'propvalue', "$copath/A/baz");
$svk->status ("$copath/A");
$svk->pl ('-v', "$copath/A/baz");
$svk->commit ('-m', 'commit message here', "$copath/A");

$svk->rm ("$copath/A/bar");
ok(!-e "$copath/A/bar");
$svk->commit ('-m', 'remove files', "$copath/A");

$svk->revert ("$copath/A/bar");
ok(!-e "$copath/A/bar");

$svk->revert ('-R', "$copath/A");
ok(!-e "$copath/A/bar");
$svk->pl ('-v', "$copath/A/baz");

$svk->status ("$copath/A");
$svk->ps ('neoprop', 'propvalue', "$copath/A/baz");
$svk->pl ("$copath/A/baz");
$svk->pl ("$copath/A");

$svk->commit ('-m', 'commit message here', "$copath/A");

$svk->ps ('-m', 'set propdirectly', 'directprop' ,'propvalue', '//A');
$svk->update ($copath);

ok (eq_hash ($xd->do_proplist ( SVK::Target->new
			      ( repos => $repos,
				copath => $corpath,
				path => '/A',
				revision => $repos->fs->youngest_rev,
			      )),
	     { directprop => 'propvalue',
	       someprop => 'propvalue',
	       moreprop => 'propvalue'}), 'prop matched');

mkdir "$copath/B";
overwrite_file ("$copath/B/foo", "foobar");
$svk->update ('-r', 3, "$copath/A");
$svk->add ("$copath/B");
$svk->commit ('-m', 'blah', "$copath/B");
ok ($xd->{checkout}->get ("$corpath/A")->{revision} == 3,
    'checkout optimzation respects existing state');
