#!/usr/bin/perl
use strict;
require 't/tree.pl';
use Test::More;
plan skip_all => "can't find utils/svk-merge" unless -x "utils/svk-merge";

plan tests => 3;
our $output;

my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('smerge');

$svk->mkdir ('-m', 'the trunk', '//trunk');
$svk->co ('//trunk', $copath);
overwrite_file ("$copath/test.pl", "#!/usr/bin/perl\nsub { 'this is sub' }\n#common\n");
$svk->add ("$copath/test.pl");
$svk->commit ('-m', 'test.pl', $copath);

$svk->cp ('-m', 'local branch of trunk', '//trunk', '//local');

overwrite_file ("$copath/test.pl", "#!/usr/bin/perl\nsub { 'this is sub on trunk' }\n#common\n\nsub newsub { undef }\n");
$svk->commit ('-m', 'change on trunk', $copath);

$svk->switch ('//local', $copath);
overwrite_file ("$copath/test.pl", "#!/usr/bin/perl -w\nsub { 'this is sub on local' }\n#common\n\nsub newsub { undef }\n");

$svk->commit ('-m', 'change on local', $copath);

is_output_like ($svk, 'sm', ['-C', '//trunk', '//local'],
		qr|1 conflict found.|);

$ENV{SVKMERGE} = 'utils/svk-merge mine';
$svk->sm ('//trunk', $copath);
is_output ($svk, 'diff', ["$copath/test.pl"],
	   [], 'svk-merge mine');
$ENV{SVKMERGE} = 'utils/svk-merge theirs';
$svk->sm ('-m', 'merge from trunk to local', '//trunk', '//local');
is_output ($svk, 'up', ["$copath"],
	   ["Syncing //local(/local) in $corpath to 6.",
	    'U   test.pl'], 'svk-merge theirs');
