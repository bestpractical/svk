#!/usr/bin/perl -w
use Test::More tests => 1;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('prop');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

$svk->checkout ('//', $copath);
mkdir ("$copath/A");
mkdir ("$copath/B");
overwrite_file ("$copath/A/foo", "foobar\nfnord\n");
overwrite_file ("$copath/A/bar", "foobar\n");
overwrite_file ("$copath/B/nor", "foobar\n");
$svk->add ("$copath/A", "$copath/B");
$svk->commit ('-m', 'init', $copath);

my $tmp = File::Temp->new;

print $tmp (<< 'TMP');
#!/bin/sh
sleep 1
cat $2
echo $1 $2
mv $2 $2.tmp
echo $1 > $2
cat $2.tmp >> $2
rm -f $2.tmp

TMP
$tmp->close;
chmod 0755, $tmp->filename;
$ENV{SVN_EDITOR} = "$tmp props";

$svk->ps ('someprop', 'somevalue', "$copath/B/nor");
$svk->commit ( $copath);
is_output ($svk, 'status', [$copath], [], 'committed correctly with editor');
