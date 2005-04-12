#!/usr/bin/perl -w
use Test::More tests => 14;
use strict;
BEGIN { require 't/tree.pl' };
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('info');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->mkdir ('//info-root', '-m', '');
$svk->checkout ('//info-root', $copath);
is_output_like ($svk, 'info', [], qr'not a checkout path');
ok ($svk->info () > 0);
chdir ($copath);

my @depot_info = ("Depot Path: //info-root", "Revision: 1", "Last Changed Rev.: 1");
my @co_info = ("Checkout Path: $corpath", @depot_info);

ok ($svk->info () == 0);
is_output ($svk, 'info', [], \@co_info);
is_output ($svk, 'info', [''], \@co_info);
is_output ($svk, 'info', [$corpath], \@co_info);

is_output ($svk, 'info', ['//info-root'], \@depot_info);
$svk->rm ('//info-root', '-m', '');

ok ($svk->info () == 0);
is_output ($svk, 'info', [], \@co_info);
is_output ($svk, 'info', [''], \@co_info);
is_output ($svk, 'info', [$corpath], \@co_info);

ok ($svk->info ('//info-root') == 0);
is_output_like ($svk, 'info', ['//info-root'], qr'Filesystem has no item');
is_output_like ($svk, 'info', ['info-root'], qr'Filesystem has no item');
