#!/usr/bin/perl -w
use Test::More tests => 9;
use strict;
use File::Temp;
BEGIN { require 't/tree.pl' };

my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('revprop');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
mkdir "$copath/A";
overwrite_file ("$copath/A/foo", "foobar1");
$svk->add("$copath/A");
$svk->commit('-m' => 'log1', "$copath/A");
overwrite_file ("$copath/A/foo", "foobar2");
$svk->commit('-m' => 'log2', "$copath/A");
is_output_like(
    $svk, 'proplist', ['--revprop'],
    qr{Unversioned properties on revision 2:\n.*  svn:date\n.*  svn:log}s,
);
is_output(
    $svk, 'propget', ['-r' => 1, '--revprop', 'svn:log'],
    ['log1']
);
is_output(
    $svk, 'propget', ['--revprop', 'svn:log'],
    ['log2']
);

is_output(
    $svk, 'propset', ['--revprop', 'svn:log', 'log2.new'],
    ["Property 'svn:log' set on repository revision 2."]
);
is_output(
    $svk, 'propget', ['--revprop', 'svn:log'],
    ['log2.new']
);

is_output(
    $svk, 'propdel', ['--revprop', 'svn:log'],
    ["Property 'svn:log' set on repository revision 2."]
);
is_output_like(
    $svk, 'proplist', ['--revprop'],
    qr{(?!.*svn:log)Unversioned properties on revision 2:\n.*  svn:date\n}s,
);

set_editor(<< 'TMP');
$_ = shift;
open _ or die $!;
@_ = ("prepended_prop\n", <_>);
close _;
unlink $_;
open _, '>', $_ or die $!;
print _ @_;
close _;
TMP

is_output(
    $svk, 'propedit', ['-r' => 1, '--revprop', 'svn:log'],
    ['Waiting for editor...', "Property 'svn:log' set on repository revision 1."]
);
is_output(
    $svk, 'propget', ['-r' => 1, '--revprop', 'svn:log'],
    ['prepended_prop', 'log1']
);
