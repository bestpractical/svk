#!/usr/bin/perl
use strict;
require Test::More;
require 't/tree.pl';
use Test::More;
eval "require SVN::Mirror; 1" or plan skip_all => 'require SVN::Mirror';
plan tests => 4;
our $output;
# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');

my $tree = create_basic_tree ($xd, '/test/');

my ($copath, $corpath) = get_copath ('svm');

my ($srepospath, $spath) =$xd->find_repos ('/test/A');

$svk->copy ('-m', 'just make some more revisions', '/test/A', "/test/A-$_") for (1..20);

$svk->mirror ('//m', "file://${srepospath}".($spath eq '/' ? '' : $spath));

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
$svk->status ($copath);

$svk->commit ('-m', 'commit to mirrored path', $copath);
ok(1);

append_file ("$copath/T/xd", "back to mirror directly again\n");
$svk->commit ('-m', 'commit to deep mirrored path', "$copath/T/xd");
ok(1);

$svk->copy ('-m', 'branch in source', '/test/A', '/test/A-98');
$svk->copy ('-m', 'branch in source', '/test/A-98', '/test/A-99');

$svk->mirror ('//m-99', "file://${srepospath}/A-99");
$svk->sync ('//m-99');

$svk->mkdir ('-m', 'bad mkdir', '//m/badmkdir');
# has some output
ok ($output =~ /under mirrored path/);
