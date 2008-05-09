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

{
    append_file ("$copath/a_file", "a change\n");
    $svk->commit ('-m', 'change a file', "$copath");

    $svk->up ('-r', '-1', "$copath");
    diag $output;
    is_output ($svk, 'cat', ["$copath/a_file"],
        ['a file']
    );
    die "XXX: if we uncomment this line then output is different, some sort of caching?";
    #$svk->st ("$copath");
    #diag $output;
    $svk->rm ("$copath/a_file");
    diag $output;
    $svk->up ('-C', "$copath");
    diag $output;
}

