#!/usr/bin/perl -w
use Test::More tests => 9;
use strict;
our $output;
require 't/tree.pl';
use SVK::Command;
my ($xd, $svk) = build_test('foo');
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');
$svk->mkdir ('-m', 'init', '//new');
my ($copath, $corpath) = get_copath ('copy');
is_output_like ($svk, 'copy', [], qr'SYNOPSIS', 'copy - help');

$svk->checkout ('//new', $copath);
# XXX: fix and check the output of copy
$svk->copy ('//V/me', '//V/D/de', $copath);
is_output ($svk, 'copy', ['//V/me', '//V/D/de', "$copath/me"],
	   ["$corpath/me is not a directory."], 'multi to nondir');
$svk->copy ('//V/me', "$copath/me-copy");
$svk->copy ('//V/D/de', "$copath/de-copy");
$svk->copy ('//V/D', "$copath/D-copy");
$svk->copy ('//V', "$copath/V-copy");
is_output ($svk, 'copy', ['//V', '/foo/bar', "$copath/V-copy"],
	   ['Different depots.']);
is_output ($svk, 'copy', ['//V/me', '//V/D', '//V/new'],
	   ["Can't copy more than one depotpath to depotpath"]);
append_file ("$copath/me-copy", "foobar");
append_file ("$copath/V-copy/D/de", "foobar");
$svk->rm ("$copath/V-copy/B/fe");
is_output ($svk, 'status', [$copath],
	   ['A + t/checkout/copy/D-copy',
	    'A + t/checkout/copy/V-copy',
	    'D   t/checkout/copy/V-copy/B/fe',
	    'M   t/checkout/copy/V-copy/D/de',
	    'A + t/checkout/copy/de',
	    'A + t/checkout/copy/de-copy',
	    'A + t/checkout/copy/me',
	    'M + t/checkout/copy/me-copy']);
$svk->commit ('-m', 'commit depot -> checkout copies', $copath);
is_copied_from ("$copath/me", '/V/me', 3);
is_copied_from ("$copath/me-copy", '/V/me', 3);
is_copied_from ("$copath/D-copy/de", '/V/D/de', 3);
is_copied_from ("$copath/D-copy", '/V/D', 3);

sub is_copied_from {
    my ($path, $source, $rev) = @_;
    $svk->info ($path);
    my ($rsource, $rrev);
    ok ((($rsource, $rrev) = $output =~ m/Copied from (.*?), Rev. (\d+)/) &&
	$source eq $rsource && $rev == $rrev);
}
