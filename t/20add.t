#!/usr/bin/perl -w
use Test::More tests => 13;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('add');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
overwrite_file ("A/foo", "foobar");
overwrite_file ("A/bar", "foobar");
overwrite_file ("A/deep/baz", "foobar");
overwrite_file ("A/deep/baz~", "foobar");

is_output_like ($svk, 'add', [], qr'SYNOPSIS', 'add - help');

is_output ($svk, 'add', ['A/foo'],
	   ['A   A', 'A   A/foo'], 'add - descendent target only');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['-q', 'A/foo'],
	   [], 'add - quiet');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ["$corpath/A/foo"],
	   ["A   $corpath/A", "A   $corpath/A/foo"], 'add - descendent target only - abspath');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['../add/A/foo'],
	   ["A   ../add/A", "A   ../add/A/foo"], 'add - descendent target only - relpath');
$svk->revert ('-R', '.');

TODO: {
local $TODO = 'get proper anchor';
is_output ($svk, 'add', ['A/deep/baz'],
	   ['A   A', 'A   A/deep', 'A   A/deep/baz'],
	   'add - deep descendent target only');
}
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['A'],
	   ['A   A', 'A   A/bar', 'A   A/foo', 'A   A/deep', 'A   A/deep/baz'],
	   'add - anchor');
$svk->revert ('-R', '.');

is_output ($svk, 'add', [qw/-N A/],
	   ['A   A'],
	   'add - nonrecursive anchor');
is_output ($svk, 'add', ['A/foo'],
	   ['A   A/foo'],
	   'add - nonrecursive target');
$svk->revert ('-R', '.');

is_output_like ($svk, 'add', ['-N', 'A/foo'],
		qr'do_add with targets and non-recursive not handled',
		'add - nonrecursive target only');

overwrite_file ("A/exe", "foobar");
chmod (0755, "A/exe");
TODO: {
local $TODO = 'notify that added file has executable bit';
is_output($svk, 'add', ['A/exe'],
	  ['A   A',
	   'A   A/exe - (bin)']);
}
$svk->commit ('-m', 'test exe bit');
unlink ('A/exe');
$svk->revert ('A/exe');
ok (-x 'A/exe');
SKIP: {

skip 'File::MimeInfo not installed', 1 unless eval 'require File::MimeInfo::Magic; 1';

overwrite_file ("A/foo.pl", "#!/usr/bin/perl\n");
overwrite_file ("A/foo.jpg", "xff\xd8\xffthis is jpeg");
overwrite_file ("A/foo.bin", "\xf0\xff\xd1\xffthis is binary");
overwrite_file ("A/foo.html", "<html>");

$svk->add ('A/foo.pl', 'A/foo.bin', 'A/foo.jpg', 'A/foo.html');
is_output ($svk, 'pl', ['-v', 'A/foo.pl', 'A/foo.bin', 'A/foo.jpg', 'A/foo.html'],
	   ['Properties on A/foo.bin:',
	    '  svn:mime-type: application/octet-stream',
	    'Properties on A/foo.jpg:',
	    '  svn:mime-type: image/jpeg',
	    'Properties on A/foo.html:',
	    '  svn:mime-type: text/html']);
}
