#!/usr/bin/perl
use Test::More tests => 2;
use strict;
require 't/tree.pl';
our $output;
my ($xd, $svk) = build_test();

is_output_like ($svk, 'help', [], qr'Available commands:');
is_output_like ($svk, 'help', ['help'], qr'SYNOPSIS');
