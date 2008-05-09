#!/usr/bin/perl -w

use strict;

use Test::More tests => 14;
use SVK::Test;

my ($xd, $svk) = build_test();
our $output;
our $answer;
our ($copath, $corpath) = get_copath ('smerge-delete');
$svk->mkdir ('-m', 'trunk', '//trunk');
$svk->checkout ('//trunk', $copath);
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;

append_file ("$copath/ticket_forcer", "tick\n");
$svk->add ("$copath/ticket_forcer");

mkdir "$copath/A";
append_file ("$copath/A/a_file", "a file\n");
$svk->add ("$copath/A");
$svk->commit ('-m', 'init', "$copath");
$svk->cp ('-m', 'branch', '//trunk', '//local');
$svk->rm ('-m', 'rm A on local', '//local/A');

# cleanup repo state
sub cleanup_repo_state {
    $svk->rm ('-m', 'rm A on local', '//local/A');
    $svk->rm ('-m', 'rm A on trunk', '//trunk/A');

    $svk->up ($copath);
    append_file ("$copath/ticket_forcer", "tick\n");
    $svk->commit ('-m', 'update ticket forcer', "$copath");
    $svk->smerge ('-m', 'smerge', '//trunk', '//local');

    $svk->mkdir ('-m', 'add A on trunk', '//trunk/A');
    $svk->smerge ('-m', 'smerge', '//trunk', '//local');

    $svk->rm ('-m', 'rm A on local again', '//local/A');

    $svk->up ($copath);
}


# test add file with returning back parrent dir
{
    append_file ("$copath/A/a_file", "a change\n");
    $svk->commit ('-m', 'change the file', "$copath");

    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (2, 5) /trunk to /local (base /trunk:2).',
    	    __"C   A",
    	    __"C   A/a_file",
    	    "Empty merge.",
            "2 conflicts found."
    	   ]);
    $answer = ['a'];
    is_output ($svk, 'smerge', ['-m', 'add file and dir back', '//trunk', '//local'],
    	   ['Auto-merging (2, 5) /trunk to /local (base /trunk:2).',
    	    __"A   A/a_file",
    	    __"A   A",
    	    "New merge ticket: $uuid:/trunk:5",
            "Committed revision 6."
    	   ]);
    is_output ($svk, 'cat', ['//local/A/a_file'],
        ['a file',
         'a change']
    );
}

