#!/usr/bin/perl
use strict;
use SVN::XD;
require Test::More;
eval "require SVN::Mirror"
or Test::More->import (skip_all => "SVN::Mirror not installed");
Test::More->import ('no_plan');
require 't/tree.pl';
package main;

# build another tree to be mirrored ourself
$svk::info = build_test ('test');

my $tree = create_basic_tree ('/test/');
my $pool = SVN::Pool->new_default;

my ($copath, $corpath) = get_copath ('smerge');
my ($scopath, $scorpath) = get_copath ('smerge-source');

my ($srepospath, $spath, $srepos) = svk::find_repos ('/test/A', 1);
my ($repospath, undef, $repos) = svk::find_repos ('//', 1);

svk::mirror ('//m', "file://${srepospath}".($spath eq '/' ? '' : $spath));

svk::sync ('//m');

svk::copy ('-m', 'branch', '//m', '//l');

svk::checkout ('/test/', $scopath);
append_file ("$scopath/A/be", "modified on source\n");
svk::commit ('-m', 'commit on source', $scopath);
svk::checkout ('//l', $copath);
append_file ("$copath/Q/qu", "modified on local\n");
svk::commit ('-m', 'commit on local', $copath);

svk::sync ('//m');

svk::merge ('-a', '-C', '//m', '//l');
svk::merge ('-a', '-C', '//l', '//m');

svk::merge ('-a', '-m', 'simple smerge from source', '//m', '//l');

my ($suuid, $srev) = ($srepos->fs->get_uuid, $srepos->fs->youngest_rev);

svk::update ($copath);

ok (eq_hash (SVN::XD::do_proplist ($svk::info,
				   repos => $repos,
				   copath => $copath,
				   path => '/l',
				   rev => $repos->fs->youngest_rev,
				  ),
	     {'svk:merge' => "$suuid:/A:$srev",
	      'svm:source' => 'file://'.$srepos->path.'!/A',
	      'svm:uuid' => $suuid }), 'simple smerge from source');

svk::merge ('-a', '-m', 'simple smerge from local', '//l', '//m');

print `svn diff -r 3:4 file://$srepospath/A/be`;

svk::sync ('//m');
print 'diff 7:8: '.`svn diff -r 7:8 file://$repospath`;
svk::merge ('-a', '-C', '//m', '//l');

#svk::proplist ('-v', $copath);

=comment

ok (-e "$corpath/A/be");
append_file ("$copath/A/be", "from local branch of svm'ed directory\n");
mkdir "$copath/A/T/";
append_file ("$copath/A/T/xd", "local new file\n");

svk::add ("$copath/A/T");
svk::delete ("$copath/B/S/P/pe");

svk::commit ('-m', 'local modification from branch', "$copath");
svk::merge (qw/-C -r 4:5/, '-m', 'merge back to remote', '//l', '//m');
svk::merge (qw/-r 4:5/, '-m', 'merge back to remote', '//l', '//m');

svk::sync ('//m');

$pool = SVN::Pool->new_default; # for some reasons

svk::merge (qw/-r 5:6/, '//m', $copath);
svk::status ($copath);

=cut

cleanup_test($svk::info)
