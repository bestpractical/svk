#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 5;
our $output;

my ($xd, $svk) = build_test('test');

$svk->mkdir(-m => 'trunk', '/test/trunk');
$svk->mkdir(-m => 'trunk', '/test/branches');
$svk->mkdir(-m => 'trunk', '/test/tags');
my $tree = create_basic_tree($xd, '/test/trunk');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

$svk->mirror('//mirror/MyProject', $uri);
$svk->sync('//mirror/MyProject');

my ($copath, $corpath) = get_copath('basic-trunk');

$svk->checkout('//mirror/MyProject/trunk', $copath);

chdir($copath);

# this should be is_output(_like) instead of just run it
# but I'm not sure what's the correct message yet
$svk->br('--offline','foo');

is_output_like ($svk, 'info', [],
   qr|Depot Path: //local/MyProject/foo|);

is_ancestor($svk, '//local/MyProject/foo', '/mirror/MyProject/trunk', 6);

is_output($svk, 'br', ['-l', '--local', '//mirror/MyProject'],
          ['foo']);
append_file('A/be', "fnordorz\n");
$svk->commit(-m => 'orz');

$svk->br('--online'); # XXX: check output

is_output_like ($svk, 'info', [],
   qr|Depot Path: //mirror/MyProject/branches/foo|);

is_ancestor($svk, '//mirror/MyProject/branches/foo', '/mirror/MyProject/trunk', 6);


exit;
TODO: {
# should online need an argument ?

# let's play with feature/foobar branch now

is_output_like ($svk, 'branch', ['--create', 'feature/foobar'],
    qr'Project branch created: feature/foobar');

$svk->br('--switch', 'feature/foobar');
is_output_like ($svk, 'info', [],
   qr|Depot Path: //mirror/MyProject/branches/feature/foobar|);

# future should be is_output_like
$svk->br('--offline'); # offline the feature/foobar branch

is_output_like ($svk, 'info', [],
   qr|Depot Path: //local/MyProject/feature/foobar|);

append_file ('B/S/Q/qu', "\nappend CBA on local branch feature/foobar\n");
$svk->commit ('-m', 'commit message','');

# now should do push first, then sw to the branch 
$svk->br('--online');

# need more message to test
}
