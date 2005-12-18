#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl';};
plan tests => 2;
our $output;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');
$svk->mkdir('-pm' => 'trunk', '/test/project/trunk');
my $tree = create_basic_tree ($xd, '/test/project/trunk');
my ($copath, $corpath) = get_copath ('view-mirror');

$svk->cp(-m => "Create $_", '/test/project/trunk/A' => "/test/project/trunk/$_")
    for 'E'..'Z';

$svk->ps ('-m', 'my view', 'svk:view:myview',
	  '&:/project/trunk
 -*
 S   S
 V   V
 K   K
', '/test/project/trunk');
is_output($svk, 'ls', ['/test/^project/trunk/myview'],
	  ['K/', 'S/', 'V/']);

my ($srepospath, $spath, $srepos) =$xd->find_repos('/test/project', 1);
my $suuid = $srepos->fs->get_uuid;
my $uri = uri($srepospath);

$svk->mi('//prj', "$uri/project");
$svk->sync('//prj');

is_output($svk, 'ls', ['//^prj/trunk/myview'],
	  ['K/', 'S/', 'V/']);
