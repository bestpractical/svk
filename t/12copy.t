#!/usr/bin/perl
use Test::More tests => 4;
use strict;
our $output;
require 't/tree.pl';
use SVK::Command;
my ($xd, $svk) = build_test();
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');
$svk->mkdir ('-m', 'init', '//new');
my ($copath, $corpath) = get_copath ('copy');

$svk->checkout ('//new', $copath);
$svk->copy ('//V/me', $copath);
$svk->copy ('//V/D/de', $copath);
$svk->copy ('//V/me', "$copath/me-copy");
$svk->copy ('//V/D/de', "$copath/de-copy");
$svk->copy ('//V/D', "$copath/D-copy");
$svk->status ($copath);
$svk->commit ('-m', 'commit depot -> checkout copies', $copath);
is_copied_from ("$copath/me", '/V/me', 3);
is_copied_from ("$copath/me-copy", '/V/me', 3);
is_copied_from ("$copath/D-copy/de", '/V/D/de', 3);
TODO: {
local $TODO = "respect directory copies";
is_copied_from ("$copath/D-copy", '/V/D', 3);
}

sub is_copied_from {
    my ($path, $source, $rev) = @_;
    $svk->info ($path);
    my ($rsource, $rrev);
    ok ((($rsource, $rrev) = $output =~ m/Copied from (.*?), Rev. (\d+)/) &&
	$source eq $rsource && $rev == $rrev);
}
