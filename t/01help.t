#!/usr/bin/perl -w
use Test::More;
use strict;
require 't/tree.pl';

plan skip_all => 'MANIFEST not exists' unless -e 'MANIFEST';
open FH, 'MANIFEST' or die $!;
my @cmd = map { chomp; s|^lib/SVK/Command/(\w+)\.pm$|$1| ? $_ : () } <FH>;

our $output;
my ($xd, $svk) = build_test();

plan tests => 2*@cmd+3;

is_output_like ($svk, 'help', [], qr'Available commands:');
is_output_like ($svk, 'nosuchcommand', [], qr'Command not recognized');
$svk->help ('--boo');
ok ($@, 'unkonwn options');

for (@cmd) {
    s|^.*/(\w+)\.pm|$1|g;
    is_output_like ($svk, 'help', [lc($_)], qr'SYNOPSIS');
    is_output_like ($svk, lc($_), ['--help'], qr'SYNOPSIS');
}
