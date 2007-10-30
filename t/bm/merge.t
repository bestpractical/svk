#!/usr/bin/perl -w
use strict;
use Test::More tests => 10;
use SVK::Test;
use File::Path;

#sub copath { SVK::Path::Checkout->copath($copath, @_) }

my ($xd, $svk) = build_test('test');
our $output;
$svk->mkdir(-m => 'trunk', '/test/trunk');
$svk->mkdir(-m => 'trunk', '/test/branches');
$svk->mkdir(-m => 'trunk', '/test/tags');
my $tree = create_basic_tree($xd, '/test/trunk');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

$svk->mirror('//mirror/MyProject', $uri);
$svk->sync('//mirror/MyProject');

my ($copath, $corpath) = get_copath ('MyProject');
$svk->checkout('//mirror/MyProject/trunk',$copath);
chdir($copath);

is_output_like ($svk, 'branch', ['--create', 'feature/foo','--switch-to'], qr'Project branch created: feature/foo');
overwrite_file ('A/be', "\nsome more foobar\nzz\n");
$svk->propset ('someprop', 'propvalue', 'A/be');
$svk->diff();
$svk->commit ('-m', 'commit message here (r8)','');
is_output ($svk, 'merge',
    ['-C', '-rHEAD:7', '//mirror/MyProject/branches/feature/foo', '//mirror/MyProject/trunk'], 
    [ "Checking locally against mirror source $uri.", 'gg  A/be']);
is_output ($svk, 'branch', ['--merge', '-C', 'feature/foo', 'trunk'], 
    [ "Checking locally against mirror source $uri.", 'gg  A/be']);

# another branch
is_output_like ($svk, 'branch', ['--create', 'feature/bar','--switch-to'], qr'Project branch created: feature/bar');
overwrite_file ('A/Q/qu', "\nonly a bar\nzz\n");
$svk->diff();
$svk->commit ('-m', 'commit message here (r10)','');
is_output ($svk, 'branch', ['--merge', '-C', 'feature/bar', 'trunk'], 
    [ "Checking locally against mirror source $uri.", 'g   A/Q/qu']);

is_output ($svk, 'branch', ['--merge', '-C', 'feature/foo', 'trunk'], 
    [ "Checking locally against mirror source $uri.", 'gg  A/be']);

is_output ($svk, 'branch', ['--merge', '-C', 'feature/bar', 'feature/foo', 'trunk'], 
    [ "Checking locally against mirror source $uri.", 'g   A/Q/qu',
      "Checking locally against mirror source $uri.", 'gg  A/be']);

is_output_like ($svk, 'branch', ['--merge', 'feature/bar', 'feature/foo', 'trunk'], 
    qr/Committed revision 13 from revision 11./);

$svk->switch ('//mirror/MyProject/trunk');
is_file_content ('A/Q/qu', "\nonly a bar\nzz\n");
is_file_content ('A/be', "\nsome more foobar\nzz\n");
