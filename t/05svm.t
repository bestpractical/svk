#!/usr/bin/perl -w
use strict;
require Test::More;
require 't/tree.pl';
use Test::More;
eval "require SVN::Mirror; 1" or plan skip_all => 'require SVN::Mirror';
plan tests => 8;
our $output;
# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');

my $tree = create_basic_tree ($xd, '/test/');

my ($copath, $corpath) = get_copath ('svm');

my ($srepospath, $spath, $srepos) =$xd->find_repos ('/test/A', 1);
my $suuid = $srepos->fs->get_uuid;

$svk->copy ('-m', 'just make some more revisions', '/test/A', "/test/A-$_") for (1..20);

my $uri = uri($srepospath);
$svk->mirror ('//m', $uri.($spath eq '/' ? '' : $spath));

$svk->sync ('//m');

$svk->copy ('-m', 'branch', '//m', '//l');
$svk->checkout ('//l', $copath);

ok (-e "$corpath/be");
append_file ("$copath/be", "from local branch of svm'ed directory\n");
mkdir "$copath/T/";
append_file ("$copath/T/xd", "local new file\n");

$svk->add ("$copath/T");
$svk->delete ("$copath/Q/qu");

$svk->commit ('-m', 'local modification from branch', "$copath");
$svk->merge (qw/-C -r 4:5/, '-m', 'merge back to remote', '//l', '//m');
$svk->merge (qw/-r 4:5/, '-m', 'merge back to remote', '//l', '//m');
$svk->sync ('//m');

#$svk->merge (qw/-r 5:6/, '//m', $copath);
$svk->switch ('//m', $copath);
$svk->update ($copath);

append_file ("$copath/T/xd", "back to mirror directly\n");
overwrite_file ("$copath/T/foo", "back to mirror directly\n");
$svk->add ("$copath/T/foo");
$svk->status ($copath);

is_output ($svk, 'commit', ['-m', 'commit to mirrored path', $copath],
	   ['Commit into mirrored path: merging back directly.',
	    "Merging back to SVN::Mirror source $uri/A.",
	    'Merge back committed as revision 24.',
	    "Syncing $uri/A",
	    'Retrieving log information from 24 to 24',
	    'Committed revision 7 from revision 24.']);
mkdir ("$copath/N");
$svk->add ("$copath/N");
is_output ($svk, 'commit', ['-m', 'commit to deep mirrored path', $copath],
	   ['Commit into mirrored path: merging back directly.',
	    "Merging back to SVN::Mirror source $uri/A.",
	    'Merge back committed as revision 25.',
	    "Syncing $uri/A",
	    'Retrieving log information from 25 to 25',
	    'Committed revision 8 from revision 25.']);
append_file ("$copath/T/xd", "back to mirror directly again\n");
$svk->commit ('-m', 'commit to deep mirrored path', "$copath/T/xd");
ok(1);

$svk->copy ('-m', 'branch in source', '/test/A', '/test/A-98');
$svk->copy ('-m', 'branch in source', '/test/A-98', '/test/A-99');

$svk->mirror ('//m-99', "$uri/A-99");
$svk->sync ('//m-99');

$svk->mkdir ('-m', 'bad mkdir', '//m/badmkdir');
# has some output
ok ($output =~ /under mirrored path/);
is_output_like ($svk, 'mirror', ['--list'],
		qr"//m.*$uri/A\n//m-99.*$uri/A-99");

is_output_like ($svk, 'delete', ['-m', 'die!', '//m-99/be'],
		qr'inside mirrored path', 'delete failed');
is_output ($svk, 'delete', ['-m', 'die!', '//m-99'],
	   ['Committed revision 12.', 'Committed revision 13.']);

