#!/usr/bin/perl -w

use strict;

use Test::More tests => 2;
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
    append_file ("$copath/A/a_file", "add a file\n");
    $svk->add ("$copath/A/a_file");
    $svk->commit ('-m', 'add a file', "$copath");

    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (2, 5) /trunk to /local (base /trunk:2).',
           #XXX: dir shouldn't be reported? May be it should be as
           # we have change in a dir that doesn't exist
    	    __"C   A",
    	    __"C   A/a_file",
    	    "Empty merge.",
            "2 conflicts found."
    	   ]);
    $answer = ['a'];
    is_output ($svk, 'smerge', ['-m', 'add file and dir back', '//trunk', '//local'],
    	   ['Auto-merging (2, 5) /trunk to /local (base /trunk:2).',
           #XXX: we want different order here, dir first children later
    	    __"A   A/a_file",
    	    __"A   A",
    	    "New merge ticket: $uuid:/trunk:5",
            "Committed revision 6."
    	   ]);
    is_output ($svk, 'cat', ['//local/A/a_file'],
        ['add a file']
    );
}

cleanup_repo_state();

# test add file with skipping it
{
    append_file ("$copath/A/a_file", "add a file\n");
    $svk->add ("$copath/A/a_file");
    $svk->commit ('-m', 'add a file', "$copath");

    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (11, 14) /trunk to /local (base /trunk:11).',
    	    __"C   A",
    	    __"C   A/a_file",
    	    "Empty merge.",
            "2 conflicts found."
    	   ]);
    $answer = ['s'];
    #XXX: I want it to be real merge as conflicts resolution is something
    # annoying to do all the time again and again
    is_output ($svk, 'smerge', ['-m', 'skip file', '//trunk', '//local'],
    	   ['Auto-merging (11, 14) /trunk to /local (base /trunk:11).',
    	    __"    A/a_file - skipped",
    	    "New merge ticket: $uuid:/trunk:14",
            "Committed revision 15."
    	   ]);
    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (14, 14) /trunk to /local (base /trunk:14).',
    	    "Empty merge.",
    	   ]);
}

cleanup_repo_state();

# test add of an empty dir with returning parent back
{
    $svk->mkdir ('-m', 'add a dir', "//trunk/A/a_dir");

    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (19, 22) /trunk to /local (base /trunk:19).',
    	    __"C   A",
    	    __"C   A/a_dir",
    	    "Empty merge.",
            "2 conflicts found."
    	   ]);
    $answer = ['a'];
    is_output ($svk, 'smerge', ['-m', 'add dir', '//trunk', '//local'],
    	   ['Auto-merging (19, 22) /trunk to /local (base /trunk:19).',
    	    __"A   A/a_dir",
    	    __"A   A",
    	    "New merge ticket: $uuid:/trunk:22",
            "Committed revision 23."
    	   ]);
    is_output ($svk, 'ls', ['//local/A/'],
        ['a_dir/']
    );
}

cleanup_repo_state();

# test skip add of an empty dir
{
    $svk->mkdir ('-m', 'add a dir', "//trunk/A/a_dir");

    is_output ($svk, 'smerge', ['-C', '//trunk', '//local'],
    	   ['Auto-merging (28, 31) /trunk to /local (base /trunk:28).',
    	    __"C   A",
    	    __"C   A/a_dir",
    	    "Empty merge.",
            "2 conflicts found."
    	   ]);
    $answer = ['s'];
    is_output ($svk, 'smerge', ['-m', 'skip dir', '//trunk', '//local'],
    	   ['Auto-merging (28, 31) /trunk to /local (base /trunk:28).',
    	    __"    A/a_dir - skiped",
    	    "New merge ticket: $uuid:/trunk:31",
            "Committed revision 32."
    	   ]);
}

