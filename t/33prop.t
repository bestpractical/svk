#!/usr/bin/perl -w
use Test::More tests => 37;
use strict;
use File::Temp;
require 't/tree.pl';

my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('basic');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
mkdir "$copath/A";
overwrite_file ("$copath/A/foo", "foobar");
overwrite_file ("$copath/A/bar", "foobarbazz");
is_output_like ($svk, 'ps', [], qr'SYNOPSIS', 'ps - help');
is_output_like ($svk, 'pe', [], qr'SYNOPSIS', 'ps - help');
is_output_like ($svk, 'propdel', [], qr'SYNOPSIS', 'propdel - help');

is_output_like ($svk, 'pl', ["$copath/A"], qr'not found');

$svk->add ($copath);
is_output ($svk, 'pl', ["$copath/A"],
	   []);
is_output ($svk, 'pl', ["$copath/A/foo"],
	   []);
$svk->commit ('-m', 'commit', $copath);
is_output ($svk, 'pl', ["$copath/A"],
	   []);

is_output ($svk, 'ps', ['myprop', 'myvalue', "$copath/A"],
	   [" M  $copath/A"]);

is_output ($svk, 'pl', ["$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop']);

is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop: myvalue']);
$svk->commit ('-m', 'commit', $copath);

is_output ($svk, 'ps', ['myprop', 'myvalue2', "$copath/A"],
	   [" M  $copath/A"]);
is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop: myvalue2']);
is_output ($svk, 'pl', ['-v', "//A"],
	   ["Properties on //A:",
	    '  myprop: myvalue']);
$svk->revert ("$copath/A");
is_output ($svk, 'ps', ['myprop2', 'myvalue2', "$copath/A"],
	   [" M  $copath/A"]);
is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop: myvalue',
	    '  myprop2: myvalue2']);
is_output ($svk, 'propdel', ['myprop', "$copath/A"],
	   [" M  $copath/A"]);
is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop2: myvalue2']);
is_output ($svk, 'pl', ['-v', "//A"],
	   ["Properties on //A:",
	    '  myprop: myvalue']);

$svk->commit ('-m', 'commit', $copath);
is_output ($svk, 'pl', ['-v', "//A"],
	   ["Properties on //A:",
	    '  myprop2: myvalue2']);
is_output ($svk, 'ps', ['-m', 'direct', 'direct', 'directly', '//A'],
	   ['Committed revision 4.']);
is_output ($svk, 'ps', ['-m', 'direct', 'direct', 'directly', '//A/foo'],
	   ['Committed revision 5.']);
#	   [' M  A']);
is_output_like ($svk, 'ps', ['-m', 'direct', 'direct', 'directly', '//A/non'],
		qr'not exist');
is_output ($svk, 'pl', ['-v', "//A"],
	   ["Properties on //A:",
	    '  direct: directly',
	    '  myprop2: myvalue2']);

is_output ($svk, 'propdel', ['-m', 'direct', 'direct','//A'],
	   ['Committed revision 6.']);
#	   [' M  A']);
$svk->update ($copath);
is_output ($svk, 'pl', ['-v', "//A"],
	   ["Properties on //A:",
	    '  myprop2: myvalue2']);

is_output ($svk, 'pl', ['-v', '-r1', '//A'],
	   []);
is_output ($svk, 'pl', ['-v', '-r1', "$copath/A"],
	   []);
is_output ($svk, 'pl', ['-v', '-r2', '//A'],
	   ["Properties on //A:",
	    '  myprop: myvalue']);
is_output ($svk, 'pl', ['-v', '-r2', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop: myvalue']);

my $tmp = File::Temp->new;

print $tmp (<< 'TMP');
#!/bin/sh
sleep 1
mv $2 $2.tmp
echo $1 > $2
cat $2.tmp >> $2
rm -f $2.tmp

TMP
$tmp->close;
chmod 0755, $tmp->filename;

$ENV{SVN_EDITOR} = "$tmp prepended_prop";

is_output ($svk, 'pe', ['newprop', "$copath/A"],
	   ['Waiting for editor...',
	    " M  $copath/A"]);

is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop2: myvalue2',
	    '  newprop: prepended_prop']);
is_output ($svk, 'pe', ['myprop2', "$copath/A"],
	   ['Waiting for editor...',
	    " M  $copath/A"]);
is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop2: prepended_prop',
	    'myvalue2',
	    '  newprop: prepended_prop']);

$svk->commit ('-m', 'commit after propedit', $copath);

is_output ($svk, 'pe', ['-m', 'commit with pe', 'pedirect', "//A"],
	   ['Waiting for editor...',
	    'Committed revision 8.']);

is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop2: prepended_prop',
	    'myvalue2',
	    '  newprop: prepended_prop']);

$svk->update ($copath);

is_output ($svk, 'pl', ['-v', "$copath/A"],
	   ["Properties on $copath/A:",
	    '  myprop2: prepended_prop',
	    'myvalue2',
	    '  newprop: prepended_prop', '',
	    '  pedirect: prepended_prop']);
chdir ("$copath/A");

is_output ($svk, 'pl', ['-v'],
	   ["Properties on .:",
	    '  myprop2: prepended_prop',
	    'myvalue2',
	    '  newprop: prepended_prop', '',
	    '  pedirect: prepended_prop']);
