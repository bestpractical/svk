#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl' };
plan_svm tests => 5;

our $output;
my ($xd, $svk) = build_test('test');
my ($copath, $corpath) = get_copath ('revspec');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
chdir ($copath);
mkdir ('A');
overwrite_file ("A/foo", "foobar\nfnord\n");
overwrite_file ("A/bar", "foobar\n");
$svk->add ('A');
$svk->commit ('-m', 'init');
$svk->cp ('//A/foo', 'foo-cp');
$svk->cp ('//A/bar', 'bar-cp');
overwrite_file ("foo-cp", "foobar\nfnord\nnewline");
$svk->ps ('mmm', 'xxx', 'A/foo');
$svk->commit ('-m', 'cp and ps');

is_output_like($svk,'log',['-r','HEAD'],qr|cp and ps|);
is_output_like($svk,'log',['-r','BASE'],qr|cp and ps|);
is_output_like($svk,'log',['-r','BASE','//A'],qr|BASE can only be issued with a check-out path|);
my ($y,$m,$d) = (localtime(time))[5,4,3];
my $date = sprintf('%04d-%02d-%02d',$y+1900,$m,$d );
is_output_like($svk,'log',['-r',"{$date}"],qr|cp and ps|);
is_output_like($svk,'log',['-r',"LLASKDJF"],qr|is not a number|);
