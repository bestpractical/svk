#!/usr/bin/perl -w
use strict;
use SVK::Util;
use Test::More tests => 3;
BEGIN { require 't/tree.pl' };

# Fake standard input
my $answer;
{
    no warnings 'redefine';
    *SVK::Util::get_prompt = sub { $answer };
}

our ($output, @TOCLEAN);
my $xd = SVK::XD->new (depotmap => {},
		       checkout => Data::Hierarchy->new);
my $svk = SVK->new (xd => $xd, output => \$output);
push @TOCLEAN, [$xd, $svk];

my $repospath = "/tmp/svk-$$-".int(rand(1000));

set_editor(<< "TMP");
\$_ = shift;
sleep 1;
open _, ">\$_" or die $!;
print _ << "EOF";
'': '$repospath'

===edit the above depot map===

EOF

TMP

$answer = 'n';
$svk->depotmap;
ok (!-e $repospath);

$answer = 'y';
$svk->depotmap ('--init');
ok (-d $repospath);
is_output_like ($svk, 'depotmap', ['--list'],
	       qr"//.*$repospath", 'depotpath - list');
rmtree [$repospath];
