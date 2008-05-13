#!/usr/bin/perl -w

use strict;

use Test::More tests => 6;
use SVK::Test;

# the source has a change in a file that is deleted in the target
# and target is a checkout

my ($xd, $svk) = build_test();
our $output;
our $answer;
our ($copath, $corpath) = get_copath ('change_in_deleted_file_co');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;

$svk->checkout ('//', $copath);
append_file ("$copath/a_file", "a file\n");
$svk->add ("$copath/a_file");
$svk->commit ('-m', 'init', "$copath");

chdir $copath;

{
    append_file ("a_file", "a change\n");
    $svk->commit ('-m', 'change a file');

    $svk->up ('-r', '-1');
    is_output ($svk, 'cat', ["a_file"],
        ['a file']
    );
    $svk->rm ("a_file");
    is_output ($svk, 'up', [ '-C'],
        ['Syncing //(/) in '.__"$corpath to 2.",
        'C   a_file',
        '1 conflict found.']
    );

    $answer = ['a'];
    is_output ($svk, 'up', [ ], [
        'Syncing //(/) in '.__"$corpath to 2.",
        'A   a_file',
    ] );
    is_output ($svk, 'cat', ["a_file"],
        ['a file', 'a change']
    );
    is_output ($svk, 'st', [ ],
        [''],
    );
}

