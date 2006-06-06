#!/usr/bin/perl -w
use Test::More tests => 1;
use strict;

BEGIN { require 't/tree.pl'; }

my ($xd, $svk) = build_test();

$svk->mkdir(-m => 'init', '//trunk');
create_basic_tree($xd, '//trunk');

my ($copath_trunk, $corpath_trunk) = get_copath('xm_trunk_co');
my ($copath_branch, $corpath_branch) = get_copath('xm_branch_co');

$svk->checkout('//trunk', $corpath_trunk);
$svk->copy(-m => "make branch", '//trunk', '//branch');

$svk->checkout('//branch', $corpath_branch);

append_file("$corpath_trunk/me", "another line in trunk");
$svk->commit(-m => 'modify on trunk', $corpath_trunk);

TODO: {
    local $TODO = 'entirely local pull should actually pull';
    # these regexps might not actually be right. The point is it should do SOMETHING with the me file::path
    is_output($svk, 'pull', [__($corpath_branch)],
              [qr/^Auto-merging/,
               qr/^U/,]);
}


