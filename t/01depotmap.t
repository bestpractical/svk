#!/usr/bin/perl -w
use Test::More tests => 3;
use strict;
BEGIN { require 't/tree.pl' };

# Fake standard input
tie *STDIN => __PACKAGE__, ('n', 'y');
sub TIEHANDLE { bless \@_ }
sub READLINE { shift @{$_[0]} }

our ($output, @TOCLEAN);
my $xd = SVK::XD->new (depotmap => {},
		       checkout => Data::Hierarchy->new);
my $svk = SVK->new (xd => $xd, output => \$output);
push @TOCLEAN, [$xd, $svk];

my $repospath = "/tmp/svk-$$";

set_editor(<< "TMP");
\$_ = shift;
sleep 1;
open _, ">\$_" or die $!;
print _ << "EOF";
'': '$repospath'

===edit the above depot map===

EOF

TMP

$svk->depotmap;
ok (!-e $repospath);
$svk->depotmap ('--init');
ok (-d $repospath);
is_output_like ($svk, 'depotmap', ['--list'],
	       qr"//.*$repospath", 'depotpath - list');
