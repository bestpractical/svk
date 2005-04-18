#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl' };
plan (skip_all => "Test does not work with BDB") if $ENV{SVNFSTYPE} eq 'bdb';
plan skip_all => "Doesn't work on win32" if $^O eq 'MSWin32';
plan_svm tests => 3;

our ($output, $answer);
my ($xd, $svk) = build_test('svm-lock');
my ($copath, $corpath) = get_copath ('svm-lock');

$svk->mkdir ('-m', 'remote trunk', '/svm-lock/trunk');
waste_rev ($svk, '/svm-lock/trunk/hate') for (1..10);

my (undef, undef, $repos) = $xd->find_repos ('//remote', 1);
my ($drepospath, $dpath, $drepos) = $xd->find_repos ('/svm-lock/trunk', 1);
my $uri = uri($drepospath);
$svk->mirror ('//remote', $uri.($dpath eq '/' ? '' : $dpath));
$svk->sync ('-a');

waste_rev ($svk, '/svm-lock/trunk/more') for (1..100);

my $pid;
if (($pid =fork) == 0) {
    $svk->sync ('-a');
    exit;
}
while ($repos->fs->youngest_rev < 23 ) {
    sleep 1;
}
waste_rev ($svk, '/svm-lock/trunk/more-hate') for (1..20);
is_output_like ($svk, 'sync', ['-a'],
		qr"Waiting for (sync|mirror) lock on //remote: .*:$pid.*Retrieving log information from 222 to 261"s);

wait;

waste_rev ($svk, '/svm-lock/trunk/more') for (1..100);
if (($pid =fork) == 0) {
    $svk->sync ('-a');
    exit;
}
waste_rev ($svk, '/svm-lock/trunk/more-hate') for (1..20);
sleep 2;
kill (15, $pid);

is_output_like ($svk, 'pl', ['-v', '--revprop', '-r', 0, '//'],
		qr'lock');

$svk->mirror ('--unlock', '//remote');
is_output_unlike ($svk, 'pl',  ['-v', '--revprop', '-r', 0, '//'],
		  qr'lock');
