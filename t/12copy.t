#!/usr/bin/perl -w
use Test::More tests => 28;
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

is_output ($svk, 'copy', ['//V/me', '//V/D/de', $copath],
	   ["A   $copath/me",
	    "A   $copath/de"]);
is_output ($svk, 'cp', ['//V/me', $copath],
	   ["Path $corpath/me already exists."]);
is_output ($svk, 'copy', ['//V/me', '//V/D/de', "$copath/me"],
	   ["$corpath/me is not a directory."], 'multi to nondir');
is_output ($svk, 'copy', ['//V/me', "$copath/me-copy"],
	   ["A   $copath/me-copy"]);
$svk->copy ('//V/D/de', "$copath/de-copy");
is_output ($svk, 'copy', ['//V/D', "$copath/D-copy"],
	   ["A   $copath/D-copy",
	    "A   $copath/D-copy/de"]);
$svk->copy ('//V', "$copath/V-copy");

is_output ($svk, 'copy', ['//V', '/foo/bar', "$copath/V-copy"],
	   ['Different depots.']);
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

is_output ($svk, 'copy', ['-m', 'more than one', '//V/me', '//V/D', '//V/new'],
	   ["Copying more than one source requires //V/new to be directory."]);

$svk->mkdir ('-m', 'directory for multiple source cp', '//V/new');
is_output ($svk, 'copy', ['-m', 'more than one', '//V/me', '//V/D', '//V/new'],
	   ["Committed revision 7."]);
is_copied_from ("//V/new/me", '/V/me', 3);
is_copied_from ("//V/new/D", '/V/D', 3);

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/foo/', 1);
create_basic_tree ($xd, '/foo/');
$svk->mirror ('//foo-remote', "file://$srepospath");
$svk->sync ('//foo-remote');
$svk->update ($copath);

is_output ($svk, 'cp', ['//V/new', '//foo-remote/new'],
	   ['Different sources.']);

is_output ($svk, 'cp', ['-m', 'copy direcly', '//V/me', '//V/me-dcopied'],
	   ['Committed revision 11.']);
is_copied_from ("//V/me-dcopied", '/V/me', 3);

is_output ($svk, 'cp', ['-m', 'copy for remote', '//foo-remote/me', '//foo-remote/me-rcopied'],
	   [
	    "Merging back to SVN::Mirror source file://$srepospath.",
	    'Merge back committed as revision 3.',
	    "Syncing file://$srepospath",
	    'Retrieving log information from 3 to 3',
	    'Committed revision 12 from revision 3.']);

is_copied_from ("//foo-remote/me-rcopied", '/foo-remote/me', 10);
is_copied_from ("/foo/me-rcopied", '/me', 2);


rmtree ([$copath]);
$svk->checkout ('//foo-remote', $copath);

is_output ($svk, 'cp', ['//V/me', "$copath/me-rcopied"],
	   ['Different sources.']);
$svk->copy ('-m', 'from co', "$copath/me", '//foo-remote/me-rcopied.again');
is_copied_from ("//foo-remote/me-rcopied.again", '/foo-remote/me', 10);
is_copied_from ("/foo/me-rcopied.again", '/me', 2);

append_file ("$copath/me", "bzz\n");
is_output_like ($svk, 'copy', ['-m', 'from co, modified', "$copath/me", '//foo-remote/me-rcopied.modified'],
		qr/modified/);
$svk->revert ('-R', $copath);
$svk->copy ("$copath/me", "$copath/me-cocopied");
is_output ($svk, 'status', [$copath],
	   ["A + $copath/me-cocopied"]
	  );

$svk->commit ('-m', 'commit copied file in mirrored path', $copath);
is_copied_from ("/foo/me-cocopied", '/me', 2);

sub is_copied_from {
    my ($path, @expected) = @_;
    $svk->info ($path);
    my ($rsource, $rrev) = $output =~ m/Copied from (.*?), Rev. (\d+)/;
    is_deeply ([$rsource, $rrev], \@expected);
}
