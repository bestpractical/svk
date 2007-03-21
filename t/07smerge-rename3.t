#!/usr/bin/perl -w

#
# Tests that smerge handles updates after renames have been made
#

use Test::More tests => 4;
use strict;
use File::Path;
use Cwd;
use SVK::Test;

my ($xd, $svk) = build_test();
our $output;
my ($co_trunk_rpath, $co_trunk_path) = get_copath ('smerge-rename3-trunk');
my ($co_branch_rpath, $co_branch_path) = get_copath ('smerge-rename3-branch');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;

# Setup the trunk
$svk->mkdir ('-m', 'trunk', '//trunk');
$svk->checkout ('//trunk', $co_trunk_path);

# Create some data in trunk
chdir($co_trunk_path);
$svk->mkdir('module');
overwrite_file('module/test.txt', '1');
$svk->add('module/test.txt');
$svk->ci(-m => "test 1");

# Make a copy
$svk->mkdir ('-m', 'trunk', '//branches');
$svk->cp(-m => 'newbranch', '//trunk', '//branches/newbranch');
$svk->checkout ('//branches/newbranch', $co_branch_path);
is_file_content("$co_branch_path/module/test.txt", '1');

# Rename the module in the branch
chdir($co_branch_path);
$svk->move('module', 'module2');
$svk->commit(-m => "renamed");

# Make a change to trunk
chdir($co_trunk_path);
overwrite_file('module/test.txt', '2');
$svk->ci(-m => "test 2");

# Merge changes w/rename from trunk to branch
$svk->smerge('//trunk', '//branches/newbranch', '--track-rename', '-m', 'merge 1');
warn $output;

# Update the branch
chdir($co_branch_path);
$svk->update();
is_file_content('module2/test.txt', '2');

# Make another change to trunk
chdir($co_trunk_path);
overwrite_file('module/test.txt', '3');
$svk->ci(-m => "test 3");

# Merge changes w/rename from trunk to branch
$svk->smerge('//trunk', '//branches/newbranch', '--track-rename', '-m', 'merge 2');

# Update the branch
chdir($co_branch_path);
$svk->update();
{ local $TODO = 'should merge in a second time too';
is_file_content('module2/test.txt', '3');
}

overwrite_file('module2/test.txt', '4');
$svk->ci(-m => "test 4");

# Merge changes w/rename from trunk to branch
$svk->smerge('//branches/newbranch', '//trunk', '--track-rename', '-m', 'merge back');

chdir($co_trunk_path);
$svk->update();
{ local $TODO = 'should merge things back too';
is_file_content('module/test.txt', '4');
}
