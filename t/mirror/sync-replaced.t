#!/usr/bin/perl -w
use strict;
use Test::More;
BEGIN { require 't/tree.pl' };
eval { require SVN::Mirror; 1 } or plan skip_all => 'require SVN::Mirror';
plan tests => 4;

my ($xd, $svk) = build_test('test');

our $output;

my $tree = create_basic_tree ($xd, '/test/');

my ($copath, $corpath) = get_copath ('sync-replaced');

$svk->checkout ('/test/', $copath);

append_file("$copath/A/Q/qu", "orz\n");
$svk->ci(-m => 'change qu', $copath);

$svk->rm("$copath/A");
$svk->cp('/test/A@2', "$copath/A");
append_file("$copath/A/Q/qu", "this is a different change\n");
#$ENV{SVKDEBUG} = 'SVK::Editor::Status';

$svk->st("$copath/A");

$svk->ci(-m => 'replace A with older A, with different change to qu', $copath);

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/', 1);
my $uri = uri($srepospath.($spath eq '/' ? '' : $spath));

$svk->mirror ('//m', $uri);
is_output($svk, 'sync', ['--to', 3, '//m'],
	  ["Syncing $uri",
	   'Retrieving log information from 1 to 3',
	   'Committed revision 2 from revision 1.',
	   'Committed revision 3 from revision 2.',
	   'Committed revision 4 from revision 3.']);

is_output($svk, 'sync', ['//m'],
	  ["Syncing $uri",
	   'Retrieving log information from 4 to 4',
	   'Committed revision 5 from revision 4.']);

is_output($svk, 'log', [-vr5 => '//m'],
	  [qr|-+|, qr|r5 \(orig r4\)|, 'Changed paths:',
	   '  R  /m/A (from /m/A:3)',
	   '  M  /m/A/Q/qu', '', 'replace A with older A, with different change to qu', qr|-+|]);

$svk->cat('/test/A/Q/qu');
my $expected = $output;

is_output($svk, 'cat', ['//m/A/Q/qu'], [split(/\n/,$output)], 'content is the same');
