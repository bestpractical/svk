#!/usr/bin/perl -w
use strict;
use Test::More tests => 2;
require 't/tree.pl';
my $pool = SVN::Pool->new;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test();

my $tree = create_basic_tree ($xd, '//');

my ($copath, $corpath) = get_copath ('switch');

$svk->cp ('-m', 'copy', '//A', '//A-branch');

$svk->checkout ('//A-branch', $copath);

overwrite_file ("$copath/Q/qu", "first line in qu\nlocally modified on branch\n2nd line in qu\n");

#$svk->switch ('-C', '//A');
$svk->switch ('//A', $copath);

ok ($xd->{checkout}->get ($corpath)->{depotpath} eq  '//A', 'switched');

is_file_content ("$copath/Q/qu", "first line in qu\nlocally modified on branch\n2nd line in qu\n");
