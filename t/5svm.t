#!/usr/bin/perl
use strict;
require Test::More;
require 't/tree.pl';
eval "require SVN::Mirror"
or Test::More->import (skip_all => "SVN::Mirror not installed");
Test::More->import ('no_plan');
package main;

# build another tree to be mirrored ourself
$svk::info = build_test ('test');

my $tree = create_basic_tree ('/test/');
my $pool = SVN::Pool->new_default;

my ($copath, $corpath) = get_copath ('svm');
my ($srepospath, $spath) = svk::find_repos ('/test/');
svk::mirror ('//m', "file://${srepospath}".($spath eq '/' ? '' : $spath));
svk::sync ('//m');

$pool = SVN::Pool->new_default; # for some reasons

svk::copy ('-m', 'branch', '//m', '//l');
svk::checkout ('//l', $copath);

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
