#!/usr/bin/perl -w
use strict;
use Test::More;
use Cwd;

BEGIN { require 't/tree.pl' };
eval { require SVN::Mirror; 1 } or plan skip_all => 'require SVN::Mirror';
plan tests => 4;

my $initial_cwd = getcwd;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');

my $tree = create_basic_tree ($xd, '/test/');

my ($copath_test, $corpath_test) = get_copath ('push-pull-test');
my ($copath_default, $corpath_default) = get_copath ('push-pull-default');

my ($test_repospath, $test_a_path, $test_repos) =$xd->find_repos ('/test/A', 1);
my $test_uuid = $test_repos->fs->get_uuid;

my ($default_repospath, $default_path, $default_repos) =$xd->find_repos ('//A', 1);
my $default_uuid = $default_repos->fs->get_uuid;

my $uri = uri($test_repospath);
$svk->mirror ('//m', $uri.($test_a_path eq '/' ? '' : $test_a_path));

$svk->sync ('//m');

$svk->copy ('-m', 'branch', '//m', '//l');
$svk->checkout ('//l', $corpath_default);

ok (-e "$corpath_default/be");
append_file ("$corpath_default/be", "from local branch\n");
mkdir "$corpath_default/T/";
append_file ("$corpath_default/T/xd", "local new file\n");

$svk->add ("$corpath_default/T");
$svk->delete ("$corpath_default/Q/qu");

$svk->commit ('-m', 'local modification from branch', "$corpath_default");

chdir ($corpath_default);
is_output ($svk, "push", [], [
        "Auto-merging (0, 5) /l to /m (base /m:3).",
        "===> Auto-merging (0, 4) /l to /m (base /m:3).",
        "Merging back to SVN::Mirror source $uri/A.",
        "Empty merge.",
        "===> Auto-merging (0, 5) /l to /m (base /m:3).",
        "Merging back to SVN::Mirror source $uri/A.",
        "D   Q/qu",
        "A   T",
        "A   T/xd",
        "U   be",
        "New merge ticket: $default_uuid:/l:5",
        "Merge back committed as revision 3.",
        "Syncing $uri/A",
        "Retrieving log information from 3 to 3",
        "Committed revision 6 from revision 3."]);

$svk->checkout ('/test/A', $corpath_test);

# add a file to remote
append_file ("$corpath_test/new-file", "some text\n");
$svk->add ("$corpath_test/new-file");

$svk->commit ('-m', 'making changes in remote depot', "$corpath_test");

chdir ($corpath_default);
is_output ($svk, "pull", [], [
        "Syncing $uri/A",
        "Retrieving log information from 4 to 4",
        "Committed revision 7 from revision 4.",
        "Auto-merging (3, 7) /m to /l (base /l:5).",
        "A   new-file",
        "New merge ticket: $test_uuid:/A:4",
        "Committed revision 8.",
        "Syncing //l(/l) in $corpath_default to 8.",
        "A   new-file"]);


# add a file to remote
append_file ("$corpath_test/new-file", "some text\n");
$svk->add ("$corpath_test/new-file");

$svk->commit ('-m', 'making changes in remote depot', "$corpath_test");

chdir ($initial_cwd);

$svk->sync ("//m");

is_output ($svk, "push", ["--from", "//m", "//l"], [
        "Auto-merging (7, 9) /m to /l (base /m:7).",
        "===> Auto-merging (7, 9) /m to /l (base /m:7).",
        "U   new-file",
        "New merge ticket: $test_uuid:/A:5",
        "Committed revision 10."]);

