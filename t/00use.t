#!/usr/bin/perl -w
use Test::More;
use File::Spec;
use File::Basename qw( dirname );

BEGIN {
    my $manifest = File::Spec->catdir( dirname(__FILE__), '..', 'MANIFEST' );

    plan skip_all => 'MANIFEST not exists' unless -e $manifest;
    open FH, $manifest;

    my @pm = map { s|^lib/||; chomp; $_ } grep { m|^lib/.*pm$| } <FH>;

    plan tests => $#pm+1;
    for (@pm) {
	s|\.pm$||;
	s|/|::|g;
	use_ok ($_);
    }
    my $svk = SVK->new;
    $svk->help;
}
