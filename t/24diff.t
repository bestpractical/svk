#!/usr/bin/perl -w
use Test::More tests => 18;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('diff');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
is_output_like ($svk, 'diff', [], qr'not a checkout path');
chdir ($copath);
mkdir ('A');
overwrite_file ("A/foo", "foobar\nfnord\n");
overwrite_file ("A/bar", "foobar\n");
overwrite_file ("A/nor", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');

overwrite_file ("A/binary", "foobar\nfnord\n");
$svk->add ('A/binary');
$svk->propset ('svn:mime-type', 'image/png', 'A/binary');
is_output ($svk, 'diff', [],
           ['=== A/binary',
            '==================================================================',
            'Cannot display: file marked as a binary type.',
            '',
            'Property changes on: A/binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' +image/png']);
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
	    '+morenewline',], 'diff - checkout dir');

is_output ($svk, 'diff', ['A/foo'],
	  [__('=== A/foo'),
	   '==================================================================',
	   __('--- A/foo  (revision 2)'),
	   __('+++ A/foo  (local)'),
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
                 '=== A/binary',
                 '==================================================================',
                 'Cannot display: file marked as a binary type.',
                 '',
                 'Property changes on: A/binary',
                 '___________________________________________________________________',
                 'Name: svn:mime-type',
                 ' +image/png',
                 '',
		 '=== A/baz',
		 '==================================================================',
		 '--- A/baz  (revision 1)',
		 '+++ A/baz  (revision 2)',
		 '@@ -0,0 +1 @@',
		 '+foobar',
		 '=== A/nor',
		 '==================================================================',
		 '--- A/nor  (revision 1)',
		 '+++ A/nor  (revision 2)',
		 '@@ -1 +0,0 @@',
		 '-foobar'];
is_sorted_output ($svk, 'diff', ['-r1:2'], $r12output, 'diff - rN:M copath');
is_sorted_output ($svk, 'diff', ['-r1:2', '//'], $r12output, 'diff - rN:M depotdir');
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
	    '+foobar',
            '=== binary',
            '==================================================================',
            'Cannot display: file marked as a binary type.',
            '',
            'Property changes on: binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' -image/png',
            '',
	    '=== baz',
	    '==================================================================',
	    '--- baz   (/A)   (revision 3)',
	    '+++ baz   (/B)   (revision 3)',
	    '@@ -1 +0,0 @@',
	    '-foobar'], 'diff - depotdir depotdir');

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
	    '=== A/nor',
	    '==================================================================',
	    '--- A/nor  (revision 1)',
	    '+++ A/nor  (local)',
	    '@@ -1 +0,0 @@',
	    '-foobar',
	    '=== A/baz',
	    '==================================================================',
	    '--- A/baz  (revision 1)',
	    '+++ A/baz  (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar',
            '=== A/binary',
            '==================================================================',
            'Cannot display: file marked as a binary type.',
            '',
            'Property changes on: A/binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' +image/png',], 'diff - rN copath (changed)');
is_sorted_output ($svk, 'diff', ['-sr1:2'],
	   ['M   A/foo',
	    'M   A/bar',
	    'A   A/binary',
	    'A   A/baz',
	    'D   A/nor']);

is_output ($svk, 'diff', ['-sr1'],
	   ['M   A/bar',
	    'M   A/foo',
	    'A   A/baz',
	    'A   A/binary',
	    'D   A/nor']);

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
	    '=== A/nor',
	    '==================================================================',
	    '--- A/nor  (revision 1)',
	    '+++ A/nor  (local)',
	    '@@ -1 +0,0 @@',
	    '-foobar',
	    '=== A/baz',
	    '==================================================================',
	    '--- A/baz  (revision 1)',
	    '+++ A/baz  (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar',
            '=== A/binary',
            '==================================================================',
            'Cannot display: file marked as a binary type.',
            '',
            'Property changes on: A/binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' +image/png'], 'diff - rN copath (unchanged)');
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

$svk->revert ('-R', 'A');

$svk->update ('-r2', 'A/bar');
append_file ("A/foo", "mixed\n");
append_file ("A/bar", "mixed\n");

is_output ($svk, 'diff', ['A/foo', 'A/bar'],
	   [__('=== A/foo'),
	    '==================================================================',
	    __('--- A/foo  (revision 1)'),
	    __('+++ A/foo  (local)'),
	    '@@ -1,2 +1,3 @@',
	    ' foobar',
	    ' fnord',
	    '+mixed',
	    __('=== A/bar'),
	    '==================================================================',
	    __('--- A/bar  (revision 2)'),
	    __('+++ A/bar  (local)'),
	    '@@ -1,2 +1,3 @@',
	    ' foobar',
	    ' newline',
	    '+mixed']);

$svk->revert ('-R', 'A');
unlink ('A/coonly');
$svk->update ;
$svk->rm ('A');

is_sorted_output ($svk, 'diff', [],
	   ['=== A/foo',
	    '==================================================================',
	    '--- A/foo  (revision 3)',
	    '+++ A/foo  (local)',
	    '@@ -1,3 +0,0 @@',
	    '-foobar',
	    '-newline',
	    '-fnord',
	    '=== A/bar',
	    '==================================================================',
	    '--- A/bar  (revision 3)',
	    '+++ A/bar  (local)',
	    '@@ -1,2 +0,0 @@',
	    '-foobar',
	    '-newline',
            '=== A/binary',
            '==================================================================',
            'Cannot display: file marked as a binary type.',
            '',
            'Property changes on: A/binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' -image/png',
            '',
	    '=== A/baz',
	    '==================================================================',
	    '--- A/baz  (revision 3)',
	    '+++ A/baz  (local)',
	    '@@ -1 +0,0 @@',
	    '-foobar'], 'recursive delete_entry');

$svk->revert ('-R', 'A');
$svk->update;
$svk->propset ('svn:mime-type', 'image/jpg', 'A/binary');
is_output ($svk, 'diff', [],
           ['',
            'Property changes on: A/binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' -image/png',
            ' +image/jpg']);
$svk->commit('-m', 'Property changes for A/binary.');
is_output ($svk, 'diff', ['-r4:3'],
           ['',
            'Property changes on: A/binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' -image/jpg',
            ' +image/png']);

# test with expanding copies
$svk->cp ('-m', 'blah', '//B', '//A/B-cp');
$svk->cp ('//A', 'C');
append_file ("C/foo", "copied and modified on C\n");

is_output ($svk, 'diff', ['C'],
	   ['=== C/B-cp/bar',
	    '==================================================================',
	    '--- C/B-cp/bar  (revision 4)',
	    '+++ C/B-cp/bar  (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar',
	    '=== C/B-cp/foo',
	    '==================================================================',
	    '--- C/B-cp/foo  (revision 4)',
	    '+++ C/B-cp/foo  (local)',
	    '@@ -0,0 +1,2 @@',
	    '+foobar',
	    '+fnord',
	    '=== C/B-cp/nor',
	    '==================================================================',
	    '--- C/B-cp/nor  (revision 4)',
	    '+++ C/B-cp/nor  (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar',
	    '=== C/bar',
	    '==================================================================',
	    '--- C/bar  (revision 4)',
	    '+++ C/bar  (local)',
	    '@@ -0,0 +1,2 @@',
	    '+foobar',
	    '+newline',
	    '=== C/baz',
	    '==================================================================',
	    '--- C/baz  (revision 4)',
	    '+++ C/baz  (local)',
	    '@@ -0,0 +1 @@',
	    '+foobar',
            '=== C/binary',
            '==================================================================',
            'Cannot display: file marked as a binary type.',
            '',
            'Property changes on: C/binary',
            '___________________________________________________________________',
            'Name: svn:mime-type',
            ' +image/jpg',
            '',
	    '=== C/foo',
	    '==================================================================',
	    '--- C/foo  (revision 4)',
	    '+++ C/foo  (local)',
	    '@@ -0,0 +1,4 @@',
	    '+foobar',
	    '+newline',
	    '+fnord',
	    '+copied and modified on C']);

# XXX: test with prop changes and also external
