#!/usr/bin/perl -w
use Test::More;
BEGIN {
    plan skip_all => 'MANIFEST not exists' unless -e 'MANIFEST';
    open FH, 'MANIFEST';

    my @pm = map { s|^lib/||; chomp; $_ } grep { m|^lib/.*pm$| } <FH>;

    plan tests => $#pm+1;
    for (@pm) {
	s|\.pm$||;
	s|/|::|g;
	use_ok ($_);
    }
    my $svk = SVK->new;
    $svk->help;
    $svk = SVK->new (xd => SVK::XD->new);
    $svk->help;
}
