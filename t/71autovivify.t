#!/usr/bin/perl -w
use strict;
use Test::More;
BEGIN { require 't/tree.pl' };
eval { require SVN::Mirror; 1 } or plan skip_all => 'require SVN::Mirror';
plan tests => 4;

our ($answer, $output);
my ($xd, $svk) = build_test();
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');

my ($copath, $corpath) = get_copath ('autovivify');
mkdir $corpath;

$answer = '//new';
is_output($svk, 'copy', [-m => '', '//V/A', "$corpath/A"], [
            'Committed revision 4.',
            "Syncing //new(/new) in ".__("$corpath/A to 4."),
            __("A   $corpath/A/Q"),
            __("A   $corpath/A/Q/qu"),
            __("A   $corpath/A/Q/qz"),
            __("A   $corpath/A/be"),
            ]);

is_output($svk, 'update', ["$corpath/A"], [
            "Syncing //new(/new) in ".__("$corpath/A to 4."),
            ]);

my ($xd2, $svk2) = build_test('test');
my $tree2 = create_basic_tree ($xd2, '/test/');
my ($srepospath, $spath, $srepos) = $xd2->find_repos ('/test/B', 1);
my $suuid = $srepos->fs->get_uuid;
my $uri = uri($srepospath);

$answer = ['', 'C', ''];
is_output($svk, 'checkout', ["$uri/C" => "$corpath/C"], [
            "New URI encountered: $uri/C/",
            "Committed revision 5.",
            "Synchronizing the mirror for the first time:",
            "  a        : Retrieve all revisions (default)",
            "  h        : Only the most recent revision",
            "  -count   : At most 'count' recent revisions",
            "  revision : Start from the specified revision",
            "Syncing $uri/C",
            "Retrieving log information from 1 to 2",
            "Committed revision 6 from revision 1.",
	    "Syncing //mirror/C/(/mirror/C) in ".__("$corpath/C to 6."),
            __("A   $corpath/C/R"),
            ]);

is_output($svk, 'update', ["$corpath/C"], [
            "Syncing //mirror/C/(/mirror/C) in ".__("$corpath/C to 6.")
            ]);
