#!/usr/bin/perl -w
use strict;
use Test::More;
BEGIN { require 't/tree.pl' };

use SVK::Util qw( can_run );

plan skip_all => 'svnadmin not in PATH'
    unless can_run('svnadmin');

plan tests => 2;

our $output;
my ($xd, $svk) = build_test();
our ($copath, $corpath) = get_copath ('admin');
is_output_like ($svk, 'admin', [], qr'SYNOPSIS', 'admin - help');
is_output ($svk, 'admin', ['lstxns'], [], 'admin - lstxns');

1;
