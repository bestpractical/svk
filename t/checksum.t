#!/usr/bin/perl -w
use strict;
use SVK::Util qw( is_executable );
use SVK::Test;
plan tests => 2;
our $output;

# Basically, trying to merge a revision containing a copy, where the cop source file is removed at the
# previous  revision, but also a copy with modification on the revision in question
#< clkao> branch from r1, r2 - remove file B, r3 - cp B@1 to C with modification, cp A@2 to B
#< clkao> so try to merge changes between r1 and r3
my ($xd, $svk) = build_test();
$svk->mkdir ('-pm', 'init', '//V/A');
my $tree = create_basic_tree ($xd, '//V/A');
my ($copath, $corpath) = get_copath ('checksum');
 
# branch from r1
$svk->cp('//V/A' => '//V/B', -m => 'r4 - A => B');
$svk->checkout('//V',$copath);

# r2 - remove file B
$svk->rm("$copath/B/me");
$svk->ci(-m => 'r5 - remove file B/me', $copath);

# r3 - cp B@1 to C with modification,
$svk->cp('//V/B/me' => '//V/Cme', -r => 4, -m => 'r6 - B/me@4 => C');
$svk->update($copath);
append_file("$copath/Cme", "mmmmmm\n");
$svk->ci(-m => 'r7 - modify Cme', $copath);
# cp A@2 to B
$svk->cp('//V/A/D/de' => '//V/B/me', -r => 5, -pm => 'r8 - A@5 => B');

chdir($copath);
$svk->merge('-r5:8','//V');
warn $output;
1;
