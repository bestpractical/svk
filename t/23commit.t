#!/usr/bin/perl -w
use Test::More tests => 20;
use strict;
BEGIN { require 't/tree.pl' };
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('commit');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
is_output_like ($svk, 'commit', [], qr'not a checkout path');
chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
mkdir ('A/deep/la');
overwrite_file ("A/foo", "foobar");
overwrite_file ("A/foo~", "foobar");
overwrite_file ("A/bar", "foobar");
overwrite_file ("A/deep/baz", "foobar");
overwrite_file ("A/deep/la/no", "foobar");

is_output ($svk, 'commit', [], ['No targets to commit.'], 'commit - no target');
$svk->add ('A');
$svk->commit ('-m', 'foo');

is_output ($svk, 'status', [], []);
overwrite_file ("A/deep/baz", "fnord");
overwrite_file ("A/bar", "fnord");
overwrite_file ("A/deep/la/no", "fnord");
overwrite_file ("A/deep/X", "fnord");
overwrite_file ("A/deep/new", "fnord");
$svk->add ('A/deep/new');
$svk->commit ('-m', 'commit from deep anchor', 'A/deep');

$svk->update ('-r', 1);
overwrite_file ("A/barnew", "fnord");
$svk->add ('A/barnew');
$svk->commit ('-m', 'nonconflict new file', 'A/barnew');
overwrite_file ("A/deep/baz", "foobar\nmodified");
is_output ($svk, 'commit', ['-m', 'conflicted new file'],
	   [qr'Transaction is out of date: .*',
	    "Please update checkout first."],
	  'commit - need update');
$svk->revert ('A/deep/baz');
overwrite_file ("A/deep/new", "this is bad");
$svk->add ('A/deep/new');
is_output ($svk, 'commit', ['-m', 'conflicted new file'],
	   [qr'Item already exists.*',
	    "Please update checkout first."],
	  'commit - need update');
$svk->revert ('A/deep/new');
unlink ('A/deep/new');
is_output ($svk, 'status', [], [__('M   A/bar'),
				__('?   A/deep/X')]);

is_deeply ([$xd->{checkout}->find ($corpath, {revision => qr/.*/})],
	   [$corpath, __"$corpath/A/barnew"]);

$svk->rm ('A/foo');
$svk->commit ('-m', 'rm something', 'A/foo');
is_deeply ([$xd->{checkout}->find ($corpath, {revision => qr/.*/})],
	   [$corpath, __("$corpath/A/barnew"), __("$corpath/A/foo")]);

# The '--sync' and '--merge' below would have no effect.
is_output ($svk, 'update', ['--sync', '--merge', $corpath], [
            "Syncing //(/) in $corpath to 4.",
            __"A   $corpath/A/deep/new",
            __"U   $corpath/A/deep/baz",
            __"U   $corpath/A/deep/la/no",
           ]);

$svk->commit ('-m', 'the rest');

is_deeply ([$xd->{checkout}->find ($corpath, {revision => qr/.*/})], [$corpath]);
$svk->rm ('A/deep/la');
$svk->commit ('-m', 'remove something deep');
is_deeply ([$xd->{checkout}->find ($corpath, {revision => qr/.*/})], [$corpath]);


is_output ($svk, 'status', [],
	   [__('?   A/deep/X')]);

unlink ('A/barnew');
mkdir ('A/forimport');
overwrite_file ("A/forimport/foo", "fnord");
overwrite_file ("A/forimport/bar", "fnord");
overwrite_file ("A/forimport/baz", "fnord");
overwrite_file ("A/forimport/ss..", "fnord");

is_output ($svk, 'commit', ['--import', '-m', 'commit --import',
			    'A/forimport', 'A/forimport/foo', 'A/forimport/bar', 'A/forimport/baz',
			    'A/barnew', 'A/forimport/ss..'],
	   ['Committed revision 7.']);

is_output ($svk, 'status', [],
	   [__('?   A/deep/X')]);

is_output ($svk, 'commit', ['--import', '-m', 'commit --import', 'A/deep/X'],
	   ['Committed revision 8.']);

is_output ($svk, 'status', [], []);
unlink ('A/forimport/foo');

is_output ($svk, 'commit', ['--import', '-m', 'commit --import', 'A/forimport/foo'],
	   ['Committed revision 9.']);
mkdir ('A/newdir');
overwrite_file ("A/newdir/bar", "fnord");
is_output ($svk, 'commit', ['--import', '-m', 'commit --import', 'A/newdir/bar'],
	   ['Committed revision 10.']);
is_output ($svk, 'status', [], [], 'import finds anchor');
$svk->update ('-r9');

overwrite_file ("A/foo", "foobar");
overwrite_file ("A/bar", "foobar");
$svk->add("A/foo", "A/bar");
$svk->commit ('-m', 'foo');

overwrite_file ("A/foo", "foobar2");
overwrite_file ("A/bar", "foobar2");

set_editor(<< 'TMP');
$_ = shift;
open _ or die $!;
# remove foo from the targets
@_ = grep !/foo/, <_>;
close _;
unlink $_;
open _, '>', $_ or die $!;
print _ @_;
close _;
print @_;
TMP

$svk->commit;
is_output ($svk, 'status', [],
	   [__('M   A/foo')]);
