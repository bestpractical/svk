#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl';};
eval { require Text::Thread; 1 }
    or plan (skip_all => "Text::Thread required for testing patchset");
plan_svm tests => 1;
our $output;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test();

my $tree = create_basic_tree ($xd, '//');

my ($copath, $corpath) = get_copath ('smerge');
$svk->checkout ('//', $copath);

my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

append_file ("$copath/A/be", "modified on trunk\n");
$svk->commit ('-m', 'modify A/be', $copath);

append_file ("$copath/D/de", "modified on trunk\n");
$svk->commit ('-m', 'modify D/de', $copath);

append_file ("$copath/D/de", "modified both\n");
append_file ("$copath/A/be", "modified both\n");
$svk->commit ('-m', 'modify A/be and D/de', $copath);

append_file ("$copath/A/Q/qu", "modified qu\n");
$svk->commit ('-m', 'modify A/qu', $copath);

use SVK::Patchset;

my $fs = $repos->fs;
my $ps = bless { xd => $xd }, 'SVK::Patchset';
$ps->recalculate ($repos);

sub node {
    my $rev = shift;
    my $log = $fs->revision_prop ($rev, 'svn:log');
    $log =~ s/\n.*$//s;
    return { title => "$rev: $log",
	     child => [map {node($_)} split /,/, ($fs->revision_prop ($rev, 'svk:children') || '')],
	   };
}

my @list = Text::Thread::formatthread
    ('child', 'threadtitle', 'title',
     # the tree
     [map {$fs->revision_prop ($_, 'svk:parents') ? () : node($_)}
      (1..$fs->youngest_rev)]);

print "$_->{threadtitle}\n" foreach @list;

is_deeply ([map {$_->{threadtitle}} @list],
	   ['1: test init tree',
	    '|->6: modify A/qu',
	    '|->4: modify D/de',
	    '| `->5: modify A/be and D/de',
	    '|->3: modify A/be',
	    '| `->5: modify A/be and D/de',
	    '`->2: test init tree',
	    '  `->4: modify D/de',
	    '    `->5: modify A/be and D/de']);
