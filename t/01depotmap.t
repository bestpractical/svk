#!/usr/bin/perl -w
use strict;
use SVK::Util qw( catdir tmpdir );
use File::Spec;
use Test::More tests => 7;
BEGIN { require 't/tree.pl' };

our ($answer, $output, @TOCLEAN);
my $xd = SVK::XD->new (depotmap => {},
		       checkout => Data::Hierarchy->new);
my $svk = SVK->new (xd => $xd, output => \$output);
push @TOCLEAN, [$xd, $svk];

my $repospath = catdir(tmpdir(), "svk-$$-".int(rand(1000)));
my $quoted = quotemeta($repospath);

set_editor(<< "TMP");
\$_ = shift;
sleep 1;
open _, ">\$_" or die $!;
print _ << "EOF";
'': '$quoted/'

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
	       qr"//.*\Q$repospath\E", 'depotpath - list');
is_output ($svk, 'depotmap', ['--delete', '//'],
	   ['New depot map saved.'], 'depotpath - delete');
is_output ($svk, 'depotmap', ['--delete', '//'],
	   ["Depot '' does not exist in the depot map."], 'depotpath - delete again');
is_output ($svk, 'depotmap', ['--add', '//', $repospath],
	   ['New depot map saved.'], 'depotpath - add');
is_output ($svk, 'depotmap', ['--add', '//', $repospath],
	   ["Depot '' already exists; use 'svk depotmap --delete' to remove it first."], 'depotpath - add again');
rmtree [$repospath];
