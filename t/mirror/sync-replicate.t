#!/usr/bin/perl -w
use strict;
use Test::More;
use SVK::Test;
use SVN::Ra;
use SVK::Mirror::Backend::SVNSync;
plan skip_all => "no replay" unless SVK::Mirror::Backend::SVNSync->has_replay_api;
plan tests => 3;
my ($xd, $svk) = build_test('test');
my ($copath, $corpath) = get_copath ('sync-replicate');

our $output;

my $tree = create_basic_tree ($xd, '/test/');
$svk->mkdir(-m => 'make dir with space.', '/test/orz dir');
$svk->mkdir(-m => 'make dir with %.', '/test/orzo%2Fdir');

$svk->mkdir(-m => 'something', '/test/orzo');

$svk->cp(-m => 'cp with % .', '/test/orzo%2Fdir', '/test/orzo%2Fdir2');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/', 1);
my $uri = uri($srepospath.($spath eq '/' ? '' : $spath));

is_output($svk, mirror => ['//', $uri],
          ["Mirror initialized.  Run svk sync // to start mirroring."]);

is_output($svk, 'sync', ['//'],
	  ["Syncing $uri",
	   'Retrieving log information from 1 to 6',
	   'Committed revision 1 from revision 1.',
	   'Committed revision 2 from revision 2.',
	   'Committed revision 3 from revision 3.',
	   'Committed revision 4 from revision 4.',
	   'Committed revision 5 from revision 5.',
	   'Committed revision 6 from revision 6.']);


is_output($svk, 'mkdir', [-m => 'fnord', '//fnord'],
	 ['Merging back to mirror source '.$uri.'.',
	  'Merge back committed as revision 7.',
	  'Syncing '.$uri,
	  'Retrieving log information from 7 to 7',
	  'Committed revision 7 from revision 7.']);
