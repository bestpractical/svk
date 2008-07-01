#!/usr/bin/perl -w

use strict;

use Test::More tests => 1;
use File::Path;
use Cwd;
use SVK::Test;

my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('smerge');
$svk->mkdir ('-m', 'trunk', '//trunk');
my $tree = create_basic_tree ($xd, '//trunk');
$svk->cp ('-m', 'branch', '//trunk', '//local');
$svk->cp ('-m', 'branch', '//local', '//local-another');
$svk->cp ('-m', 'branch', '//local-another', '//local-another-local');
$svk->co ('//trunk', $copath);
append_file("$copath/me", "a change\n");
$svk->ci ('-m', 'change file', $copath );

$svk->switch ('//local-another-local', $copath);
append_file("$copath/A/be", "a change\n");
$svk->ci ('-m', 'change file', $copath );
$svk->sm ('-Il', '//local-another-local', '//local-another' );

$svk->switch ('//local', $copath);
$svk->sm ('//trunk', $copath);

$svk->switch ('//local-another', $copath);
is_output($svk, 'diff', [$copath],
    [
    '=== t/checkout/smerge/me',
    '==================================================================',
    "--- t/checkout/smerge/me\t(revision 9)",
    "+++ t/checkout/smerge/me\t(local)",
    '@@ -1,2 +1,3 @@',
    ' first line in me',
    ' 2nd line in me - mod',
    '+a change',
    '',
    'Property changes on: t/checkout/smerge',
    '___________________________________________________________________',
    'Name: svk:merge',
    ' -006e7783-1232-49bc-9c32-34e58aa7cb2d:/trunk:3',
    ' +006e7783-1232-49bc-9c32-34e58aa7cb2d:/trunk:7',
    ]
);
