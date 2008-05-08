#!/usr/bin/perl -w

use strict;

use Test::More tests => 3;
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

