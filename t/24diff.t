#!/usr/bin/perl
use Test::More tests => 7;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('commit');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
overwrite_file ("A/foo", "foobar\nfnord\n");
overwrite_file ("A/bar", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');

overwrite_file ("A/foo", "foobar\nnewline\nfnord\n");
overwrite_file ("A/bar", "foobar\nnewline\n");
overwrite_file ("A/baz", "foobar\n");
$svk->add ('A/baz');
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
	  ['=== /A/foo',
	   '==================================================================',
	   '--- /A/foo  (revision 2)',
	   '+++ /A/foo  (local)',
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
is_output ($svk, 'diff', ['-r1:2'],$r12output, 'diff - rN:M copath');

is_output ($svk, 'diff', ['-r1:2', '//'], $r12output, 'diff - rN:M depotdir');
is_output ($svk, 'diff', ['-r1:2', '//A/foo'],
	   ['=== /A/foo',
	    '==================================================================',
	    '--- /A/foo  (revision 1)',
	    '+++ /A/foo  (revision 2)',
	    '@@ -1,2 +1,3 @@',
	    ' foobar',
	    '+newline',
	    ' fnord'], 'diff - rN:M depotfile');
TODO: {
local $TODO = 'rN depot vs copath needs revisit';
is_output ($svk, 'diff', ['-r1'],
	   ['=== A/foo',
	    '==================================================================',
	    '--- A/foo  (revision 1)',
	    '+++ A/foo  (local)',
	    '@@ -1,2 +1,4 @@',
	    ' foobar',
	    '+newline',
	    ' fnord',
	    '+morenewline'], 'diff - rN copath');
}

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
	    '-newline'], 'diff - depotdir depotdir');

# XXX: test with delete_entry and prop changes and also external
