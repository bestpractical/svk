#!/usr/bin/perl -w
use Test::More tests => 25;
use strict;
require 't/tree.pl';
our $output;

my ($xd, $svk) = build_test('bob');

is_output_like ($svk, 'ls', ['http://foobar'], qr|not a checkout path|, 'bad path');

foreach my $depot ('','bob') {
    my ($copath) = get_copath ("list$depot");
    $svk->checkout ("/$depot/", $copath);
    chdir ("$copath");
    mkdir ('A');
    overwrite_file ("A/foo", "foobar\n");
    $svk->add ('A');
    $svk->commit ('-m', 'init');
    mkdir('A/B');
    overwrite_file('A/B/foo',"foobar\n");
    $svk->add ('A/B');
    $svk->commit ('-m', 'dir B');

    is_output ($svk, 'ls', [], ['A/']);
    is_output ($svk, 'ls', ['-r1', 'A'], ['foo']);
    is_output ($svk, 'ls', ['A/foo'], []);
    is_output ($svk, 'ls', ['-R', 'A'], ['B/', ' foo', 'foo']);
    is_output ($svk, 'ls', ['-R', '-d1'], ['A/', ' B/', ' foo']);
    is_output ($svk, 'ls', ['-f','A/foo'], []);
    is_output ($svk, 'ls', ["/$depot/"], ['A/']);
    is_output ($svk, 'ls', ['-f',"/$depot/"], ["/$depot/A/"]);
    is_output ($svk, 'ls', ['-f',"/$depot/A"],  ["/$depot/A/B/", "/$depot/A/foo"]);
    is_output ($svk, 'ls', ['-f',"/$depot/A/"],
	       ["/$depot/A/B/","/$depot/A/foo"]);
    is_output ($svk, 'ls', ['-f','-R',"/$depot/A/"], ["/$depot/A/B/","/$depot/A/B/foo", "/$depot/A/foo"]);
    is_output ($svk, 'ls', ['-f',"/$depot/crap/"], ['Path /crap is not a versioned directory']);
    chdir("..");
}

