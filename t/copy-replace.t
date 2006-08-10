#!/usr/bin/perl -w
use Test::More tests => 2;
use strict;
our $output;
BEGIN { require 't/tree.pl' };
my ($xd, $svk) = build_test();
$svk->mkdir ('-pm', 'init', '//V/Y');
my $tree = create_basic_tree ($xd, '//V/Y');
my ($copath, $corpath) = get_copath ('replaced');

$svk->cp('//V/Y' => '//V/X', -m => 'Y => X');

$svk->checkout('//V', $copath);

$svk->rm("$copath/Y");
$svk->cp('//V/X' => "$copath/Y");

is_output($svk, 'st', [$copath],
	  [__('R + t/checkout/replaced/Y')]);

$svk->ci(-m => 'go', $copath);

$svk->rm("$copath/Y");
$svk->cp('//V/X' => "$copath/Y");
$svk->rm("$copath/Y/D");
is_output($svk, 'st', [$copath],
	  [__('R + t/checkout/replaced/Y'),
	   __('D + t/checkout/replaced/Y/D'),
	   __('D + t/checkout/replaced/Y/D/de')]);