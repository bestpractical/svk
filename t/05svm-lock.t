#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl' };
plan skip_all => "Doesn't work on win32" if $^O eq 'MSWin32';
plan_svm tests => 1;

our ($output, $answer);
my ($xd, $svk) = build_test('svm-lock');
my ($copath, $corpath) = get_copath ('svm-lock');

$svk->mkdir ('-m', 'remote trunk', '/svm-lock/trunk');
waste_rev ($svk, '/svm-lock/trunk/hate') for (1..10);

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
waste_rev ($svk, '/svm-lock/trunk/more-hate') for (1..20);
sleep 2;
is_output_like ($svk, 'sync', ['-a'],
		qr"Waiting for mirror lock on /remote: .*:$pid.*Retrieving log information from 222 to 261"s);

wait;
