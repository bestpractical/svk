#!/usr/bin/perl -w

use strict;

use Test::More tests => 6;
use SVK::Test;

# the source has a change in a file that is deleted in the target

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
$svk->commit ('-m', 'init', "$copath");

$svk->cp ('-m', 'branch', '//trunk', '//local');

append_file ("$copath/a_file", "a file\n");
$svk->add ("$copath/a_file");
$svk->commit ('-m', 'add a file', "$copath");
$svk->sm ('-m', 'smerge', '//trunk', '//local');
$svk->rm ('-m', 'rm the file on local', '//local/a_file');

# cleanup repo state
sub cleanup_repo_state {
    $svk->rm ('-m', 'rm on local', '//local/a_file');
    $svk->rm ('-m', 'rm on trunk', '//trunk/a_file');

    $svk->up ($copath);
    append_file ("$copath/ticket_forcer", "tick\n");
    $svk->commit ('-m', 'update ticket forcer', "$copath");
    $svk->smerge ('-m', 'smerge', '//trunk', '//local');

    $svk->up ($copath);
    overwrite_file ("$copath/a_file", "a file\n");
    $svk->add ("$copath/a_file");
    $svk->commit ('-m', 'add file', "$copath");
    $svk->smerge ('-m', 'smerge', '//trunk', '//local');

    $svk->rm ('-m', 'rm on local again', '//local/a_file');

    $svk->up ($copath);
}

# test change of a file in src when file doesn't exist in dst with a)dd resolver action
{
    append_file ("$copath/a_file", "a change\n");
    $svk->commit ('-m', 'change a file', "$copath");

    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (4, 7) /trunk to /local (base /trunk:4).',
    	    __"C   a_file",
    	    "Empty merge.",
            "1 conflict found."
    	   ]);
    $answer = ['a'];
    is_output ($svk, 'smerge', ['-m', 'add file and dir back', '//trunk', '//local'],
    	   ['Auto-merging (4, 7) /trunk to /local (base /trunk:4).',
    	    __"A   a_file",
    	    "New merge ticket: $uuid:/trunk:7",
            "Committed revision 8."
    	   ]);
    is_output ($svk, 'cat', ['//local/a_file'],
        ['a file',
         'a change']
    );
}

cleanup_repo_state();

# test change of a file in src when file doesn't exist in dst with s)kip resolver action
{
    append_file ("$copath/a_file", "a change\n");
    $svk->commit ('-m', 'change a file', "$copath");

    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (13, 16) /trunk to /local (base /trunk:13).',
    	    __"C   a_file",
    	    "Empty merge.",
            "1 conflict found."
    	   ]);
    $answer = ['s'];
    is_output ($svk, 'smerge', ['-m', 'skip file change', '//trunk', '//local'],
    	   ['Auto-merging (13, 16) /trunk to /local (base /trunk:13).',
    	    "New merge ticket: $uuid:/trunk:16",
            "Committed revision 17."
    	   ]);
    is_output ($svk, 'cat', ['//local/a_file'],
        ["Filesystem has no item: File not found: revision 17, path '/local/a_file'"]
    );
}

