#!/usr/bin/perl
use Test::More tests => 9;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('diff');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
overwrite_file ("A/foo", "foobar\nfnord\n");
overwrite_file ("A/bar", "foobar\n");
overwrite_file ("A/nor", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');

overwrite_file ("A/foo", "foobar\nnewline\nfnord\n");
overwrite_file ("A/bar", "foobar\nnewline\n");
overwrite_file ("A/baz", "foobar\n");
$svk->add ('A/baz');
$svk->rm ('A/nor');
$svk->commit ('-m', 'some modification');
overwrite_file ("A/foo", "foobar\nnewline\nfnord\nmorenewline\n");
is_output ($svk, 'diff', [],
	   ['=== A/foo',
	    '==================================================================',
	    '--- A/foo  (revision 2)',
	    '+++ A/foo  (local)',
	    '@@ -1,3 +1,4 @@',
	    ' foobar',
	    ' newline',
	    ' fnord',
	    '+morenewline'], 'diff - checkout dir');
is_output ($svk, 'diff', ['A/foo'],
	  ['=== A/foo',
	   '==================================================================',
	   '--- A/foo  (revision 2)',
	   '+++ A/foo  (local)',
	   '@@ -1,3 +1,4 @@',
	   ' foobar',
	   ' newline',
	   ' fnord',
	   '+morenewline'], 'diff - checkout file');
my $r12output = ['=== A/foo',
		 '==================================================================',
		 '--- A/foo  (revision 1)',
		 '+++ A/foo  (revision 2)',
		 '@@ -1,2 +1,3 @@',
		 ' foobar',
		 '+newline',
		 ' fnord',
		 '=== A/bar',
		 '==================================================================',
		 '--- A/bar  (revision 1)',
		 '+++ A/bar  (revision 2)',
		 '@@ -1 +1,2 @@',
		 ' foobar',
		 '+newline',
		 '=== A/baz',
		 '==================================================================',
		 '--- A/baz  (revision 1)',
		 '+++ A/baz  (revision 2)',
		 '@@ -0,0 +1 @@',
		 '+foobar'];
is_output ($svk, 'diff', ['-r1:2'], $r12output, 'diff - rN:M copath');
is_output ($svk, 'diff', ['-r1:2', '//'], $r12output, 'diff - rN:M depotdir');
is_output ($svk, 'diff', ['-r1:2', '//A/foo'],
	   ['=== foo',
	    '==================================================================',
	    '--- foo  (revision 1)',
	    '+++ foo  (revision 2)',
	    '@@ -1,2 +1,3 @@',
	    ' foobar',
	    '+newline',
	    ' fnord'], 'diff - rN:M depotfile');
$svk->cp ('-m', 'copy', '-r1', '//A', '//B');
is_output ($svk, 'diff', ['//A', '//B'],
	   ['=== foo',
	    '==================================================================',
	    '--- foo   (/A)   (revision 3)',
	    '+++ foo   (/B)   (revision 3)',
	    '@@ -1,3 +1,2 @@',
	    ' foobar',
	    '-newline',
	    ' fnord',
	    '=== bar',
	    '==================================================================',
	    '--- bar   (/A)   (revision 3)',
	    '+++ bar   (/B)   (revision 3)',
	    '@@ -1,2 +1 @@',
	    ' foobar',
	    '-newline',
	    '=== nor',
	    '==================================================================',
	    '--- nor   (/A)   (revision 3)',
	    '+++ nor   (/B)   (revision 3)',
	    '@@ -0,0 +1 @@',
	    '+foobar'], 'diff - depotdir depotdir');
is_output ($svk, 'diff', ['-r1'],
	   ['=== A/bar',
	    '==================================================================',
	    '--- A/bar  (revision 1)',
	    '+++ A/bar  (local)',
	    '@@ -1 +1,2 @@',
	    ' foobar',
	    '+newline',
	    '=== A/foo',
	    '==================================================================',
	    '--- A/foo  (revision 1)',
	    '+++ A/foo  (local)',
	    '@@ -1,2 +1,4 @@',
	    ' foobar',
	    '+newline',
	    ' fnord',
	    '+morenewline',
	    '=== A/baz',
	    '==================================================================',
	    '--- A/baz  (revision 1)',
	    '+++ A/baz  (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar'], 'diff - rN copath (changed)');
$svk->revert ('-R', 'A');
is_output ($svk, 'diff', ['-r1'],
	   ['=== A/bar',
	    '==================================================================',
	    '--- A/bar  (revision 1)',
	    '+++ A/bar  (local)',
	    '@@ -1 +1,2 @@',
	    ' foobar',
	    '+newline',
	    '=== A/foo',
	    '==================================================================',
	    '--- A/foo  (revision 1)',
	    '+++ A/foo  (local)',
	    '@@ -1,2 +1,3 @@',
	    ' foobar',
	    '+newline',
	    ' fnord',
	    '=== A/baz',
	    '==================================================================',
	    '--- A/baz  (revision 1)',
	    '+++ A/baz  (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar'], 'diff - rN copath (unchanged)');
$svk->update ('-r1', 'A');
overwrite_file ("A/coonly", "foobar\n");
$svk->add ('A/coonly');
is_output ($svk, 'diff', ['//B', 'A'],
	   ['=== coonly',
	    '==================================================================',
	    '--- coonly   (/B)   (revision 3)',
	    '+++ coonly   (/A)   (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar'],
	   'diff - depopath copath');

# XXX: test with delete_entry and prop changes and also external
