#!/usr/bin/perl -w
use Test::More tests => 6;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('annotate');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);

is_output_like ($svk, 'blame', ['--help'], qr'SYNOPSIS', 'annotate - help');
is_output_like ($svk, 'blame', [], qr'SYNOPSIS', 'annotate - help');

chdir ($copath);
mkdir ('A');
overwrite_file ("A/foo", "foobar\nbarbar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');
overwrite_file ("A/foo", "#!/usr/bin/perl -w\nfoobar\nbarbaz\n");
$svk->commit ('-m', 'more');
overwrite_file ("A/foo", "#!/usr/bin/perl -w\nfoobar\nbarbaz\nfnord\nahh");
$svk->commit ('-m', 'and more');
overwrite_file ("A/foo", "#!/usr/bin/perl -w\nfoobar\nat checkout\nbarbaz\nfnord\nahh");

is_annotate (['A/foo'], [2,1,undef,2,3,3], 'annotate - checkout');
is_annotate (['//A/foo'], [2,1,2,3,3], 'annotate - depotpath');

$svk->cp ('-m', 'copy', '//A/foo', '//A/bar');
$svk->update ;
is_annotate (['A/bar'], [4,4,4,4,4], 'annotate - copied not cross');
is_annotate (['-x', 'A/bar'], [2,1,2,3,3], 'annotate - copied');

sub is_annotate {
    my ($arg, $annotate, $test) = @_;
    $svk->annotate (@$arg);
    my @out = map {m/(\d+).*\(/; $1}split ("\n", $output);
    splice @out, 0, 2,;
    is_deeply (\@out, $annotate,
	       $test);
}
