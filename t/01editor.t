#!/usr/bin/perl -w
use Test::More tests => 1;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('prop');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

$svk->checkout ('//', $copath);
mkdir ("$copath/A");
mkdir ("$copath/B");
overwrite_file ("$copath/A/foo", "foobar\nfnord\n");
overwrite_file ("$copath/A/bar", "foobar\n");
overwrite_file ("$copath/B/nor", "foobar\n");
$svk->add ("$copath/A", "$copath/B");
$svk->commit ('-m', 'init', $copath);

my $tmp = File::Temp->new( SUFFIX => '.pl' );

print $tmp (<< 'TMP');
$_ = shift;
print "# props $_\n";
open _ or die $!;
@_ = ("props\n", <_>);
close _;
unlink $_;
sleep 2;
open _, '>', $_ or die $!;
print _ @_;
close _;
TMP
$tmp->close;

my ($perl, $tmpfile) = ($^X, $tmp->filename);
if (defined &Win32::GetShortPathName) {
    $perl = Win32::GetShortPathName($perl);
    $tmpfile = Win32::GetShortPathName($tmpfile);
}
$ENV{SVN_EDITOR} = "$perl $tmp";

$svk->ps ('someprop', 'somevalue', "$copath/B/nor");
$svk->commit ( $copath);
is_output ($svk, 'status', [$copath], [], 'committed correctly with editor');
