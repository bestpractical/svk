#!/usr/bin/perl -w
use Test::More;
use strict;
require 't/tree.pl';

plan skip_all => 'MANIFEST not exists' unless -e 'MANIFEST';
open FH, 'MANIFEST' or die $!;
my @cmd = map { chomp; s|^lib/SVK/Command/(\w+)\.pm$|$1| ? $_ : () } <FH>;

our $output;
my ($xd, $svk) = build_test();

plan tests => ( 6 + ( 2 * @cmd ) );

is_output_like ($svk, 'help', [], qr'topics');
is_output_like ($svk, 'help', ['commands'], qr'Available commands:');
is_output ($svk, 'nosuchcommand', [], ["Command not recognized, try $0 help."]);
is_output ($svk, 'bad:command/', [], ["Command not recognized, try $0 help."]);

{
    my $warned = 0;
    local $SIG{__WARN__} = sub { $warned++ };
    is_output ($svk, 'help', ['--boo'], ['Unknown options.']);
    ok($warned, 'Unknown option raised a warning');
}

for (@cmd) {
    s|^.*/(\w+)\.pm|$1|g;
    is_output_like ($svk, 'help', [lc($_)], qr'SYNOPSIS');
    is_output_like ($svk, lc($_), ['--help'], qr'SYNOPSIS');
}
