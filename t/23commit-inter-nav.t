#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl' };
plan tests => 50;

our $output;
our $answer;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('commit-inter-navi');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
mkdir ('A/deep/la');
overwrite_file ("A/foo", "foobar\ngrab\n");
overwrite_file ("A/deep/baz", "makar");
overwrite_file ("A/deep/la/no", "foobar");
overwrite_file ("A/deep/mas", "po\nkra\nczny");

$svk->add ('A');

$answer = ['p','a','a','a','p','','p','s','p','p','A','p','A','p','s','a','stop'];
our $DEBUG = 1;
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
exit;

is_output ($svk, 'status', [],
   ['A   A/deep',
    'A   A/deep/baz',
    'A   A/deep/la',
    'A   A/deep/la/no',
    'A   A/deep/mas'], 'skip subdirectory');

#our $show_prompt_output = 1;
$svk->propset('roch', 'miata', 'A/deep');
$answer = ['a','a','A','s','s','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [],
   ['A   A/deep/mas',
    ' M  A/deep'], 'accept subdirectory, skip file');

$answer = ['s','a','stop'];
$svk->propset('tada', 'bob', 'A/deep/mas');
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
# XXX: this should show info about property
is_output ($svk, 'status', [],
   ['A   A/deep/mas'], 'skip file with property');
is_output ($svk, 'diff', [],
   ['=== A/deep/mas',
    '==================================================================',
    "--- A/deep/mas\t(revision 3)",
    "+++ A/deep/mas\t(local)",
    '@@ -0,0 +1,3 @@',
    '+po',
    '+kra',
    '+czny',
    '\ No newline at end of file',
    '',
    'Property changes on: A/deep/mas',
    '___________________________________________________________________',
    'Name: tada',
    ' +bob',
    ''], 'skip file with property - test prop');

$answer = ['a','s','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');

is_output ($svk, 'diff', [],
   ['',
    'Property changes on: A/deep/mas',
    '___________________________________________________________________',
    'Name: tada',
    ' +bob',
    ''], 'commit file, skip property');

$answer = ['k','p','s','a','stop'];
$svk->propset('bata', 'rob', 'A/deep/mas');
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['',
    'Property changes on: A/deep/mas',
    '___________________________________________________________________',
    'Name: bata',
    ' +rob',
    ''], 'skip only one property');

$answer = ['a','p','c','s','stop'];
$svk->propset('bata', 'koro', 'A/deep');
$svk->propset('zoot', 'wex', 'A/deep/mas');
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['',
    'Property changes on: A/deep/mas',
    '___________________________________________________________________',
    'Name: zoot',
    ' +wex',
    ''], 'skip all \'bata\' properties');

overwrite_file ("A/deep/mas", "wy\nkra\nkal\n");
$svk->propset('parra', 'kok', 'A/deep/mas');
$answer = ['S','p','A','a','p','','p','p','p','k','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['=== A/deep/mas',
    '==================================================================',
    "--- A/deep/mas\t(revision 6)",
    "+++ A/deep/mas\t(local)",
    '@@ -1,3 +1,3 @@',
    '-po',
    '+wy',
    ' kra',
    '-czny',
    '\ No newline at end of file',
    '+kal',
    '',
    'Property changes on: A/deep/mas',
    '___________________________________________________________________',
    'Name: parra',
    ' +kok',
    'Name: zoot',
    ' +wex',
    ''], 'skip all changes to content and properties');

$answer = ['s','p','','p','S','p','A','c','p','s','s','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['',
    'Property changes on: A/deep/mas',
    '___________________________________________________________________',
    'Name: parra',
    ' +kok',
    'Name: zoot',
    ' +wex',
    ''], 'commit only content changes');

overwrite_file ("A/deep/mas", "wy\npstry\nkal\n");
overwrite_file ("A/foo", "temp");
$answer = ['S','p','c','p','a','p','c','s','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [],
    ['M   A/foo'], 'commit all changes to content and properties');

$svk->revert("A/foo");
$svk->propset('parra', 'kok', '.');
$answer = ['s','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['',
    'Property changes on: ',
    '___________________________________________________________________',
    'Name: parra',
    ' +kok',
    ''], 'skip change to root directory');

$svk->propset('parra', 'kok', '.');
$answer = ['a','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [], [], 'commit change to root directory');

overwrite_file ("A/foo", "za\ngrab\nione\n");
$answer = ['s','s','stop'];
$svk->commit('--interactive', 'A/foo', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['=== A/foo',
    '==================================================================',
    "--- A/foo\t(revision 9)",
    "+++ A/foo\t(local)",
    '@@ -1,2 +1,3 @@',
    '-foobar',
    '+za',
    ' grab',
    '+ione'], 'skiped content change to directly passed file');

$svk->propset('papa', 'mot', 'A/foo');
overwrite_file ("A/foo", "za\ngrab\nione\n");
$answer = ['k','stop'];
$svk->commit('--interactive', 'A/foo', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['=== A/foo',
    '==================================================================',
    "--- A/foo\t(revision 9)",
    "+++ A/foo\t(local)",
    '@@ -1,2 +1,3 @@',
    '-foobar',
    '+za',
    ' grab',
    '+ione',
    '',
    'Property changes on: A/foo',
    '___________________________________________________________________',
    'Name: papa',
    ' +mot',
    ''], 'skiped content and prop change to directly passed file');

$answer = ['A','s','stop'];
$svk->commit('--interactive', 'A/foo', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'diff', [],
   ['',
    'Property changes on: A/foo',
    '___________________________________________________________________',
    'Name: papa',
    ' +mot',
    ''], 'commited content, skiped prop to directly passed file');

$answer = ['a','stop'];
$svk->commit('--interactive', 'A/foo', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [], [], 'commit prop changes to directly passed file');

our $show_prompt=1;
$svk->merge('-r1', '//A/foo', 'A/deep/mas');
overwrite_file ("A/foo", "za\npalny\n");
$answer = ['n','stop'];
is_output($svk, 'commit', ['--interactive', '-m', 'foo'],
    ['Conflict detected in:',
     '  A/deep/mas',
     'file. Do you want to skip it and commit other changes? (y/n) ',
     '1 conflict detected. Use \'svk resolved\' after resolving them.'],
     'conflict - output');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [],
    ['CM  A/deep/mas',
     'M   A/foo'], 'conflict - abort');

$show_prompt=0;
$answer = ['y','a','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [],
    ['CM  A/deep/mas'], 'conflict - skip');

$show_prompt=1;
$svk->merge('-r1', '//A/foo', 'A/deep/baz');
overwrite_file ("A/foo", "");
$answer = ['n','stop'];
is_output($svk, 'commit', ['--interactive', '-m', 'foo'],
    ['Conflict detected in:',
     '  A/deep/baz',
     '  A/deep/mas',
     'files. Do you want to skip those and commit other changes? (y/n) ',
     '2 conflicts detected. Use \'svk resolved\' after resolving them.'],
     'multiple conflicts -  output');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [],
    ['CM  A/deep/baz',
     'CM  A/deep/mas',
     'M   A/foo'], 'multiple conflicts - abort');

$show_prompt=0;
$answer = ['y','a','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [],
    ['CM  A/deep/baz',
     'CM  A/deep/mas'], 'multiple conflicts- skip');

$svk->revert('A/deep/baz', 'A/deep/mas');
$svk->propset('svn:mime-type', 'faked/type', 'A/deep/mas');
overwrite_file ("A/deep/mas", "baran\nkoza\nowca\n");
$show_prompt=1;
$answer = ['c','stop'];
is_output($svk, 'commit', ['--interactive', '-m', 'foo'],
    ['',                                     
     '[1/2] Modifications to binary file \'A/deep/mas\':',
     '[a]ccept, [s]kip this change,',
     'a[c]cept, s[k]ip rest of changes to this file and its properties > ',
     'Committed revision 14.'],
     'replace file with binary one - output');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [], [], 'replace file with binary one');

$svk->propset('svn:mime-type', 'text/plain', 'A/deep/mas');
overwrite_file ("A/deep/mas", "krowa\nkoza\n");
$show_prompt=0;
$answer = ['a','a','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [], [], 'replace binary file with text one');

overwrite_file ("A/deep/mas", "byk\nkrowa\nbawol\nkoza\nkaczka\n");
$answer = ['a','a','a','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_deeply($answer, ['stop'], 'all answers used');
is_output ($svk, 'status', [], [], 'replace text file with text one');

#our $show_prompt_output=1;
$svk->propset('kox', 'ob', 'A/deep');
overwrite_file ("A/deep/mas", "mleczna\nkrowa\n");
$answer = ['A','p','a','a','s','stop'];
$svk->commit('--interactive', '-m', 'foo');
is_output ($svk, 'status', [],
    [' M  A/deep'], 'skip directory property on used directory.');
is_deeply($answer, ['stop'], 'all answers used');

