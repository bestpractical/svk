#!/usr/bin/perl -w
use strict;
use Test::More;
use Cwd;

BEGIN { require 't/tree.pl' };
eval { require SVN::Mirror; 1 } or plan skip_all => 'require SVN::Mirror';
plan tests => 6;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('mv_test');
my $tree = create_basic_tree ($xd, '/mv_test/');
my ($test_repospath, $test_a_path, $test_repos) = $xd->find_repos ('/mv_test/A', 1);

my $uri = uri($test_repospath);
$svk->mirror ('//mv/m', $uri.($test_a_path eq '/' ? '' : $test_a_path));

TODO: {
    local $TODO = "Update the svm:mirror property when moving mirrored paths";

    $svk->move ('-m', 'moving mirrored path', '//mv/m', '//mv/m2');
    is_output_like ($svk, 'propget', ['svm:mirror', '//'], qr'//mv/m2');

    $svk->move ('-m', 'moving tree containing mirrored path', '//mv', '//mv2');
    is_output_like ($svk, 'propget', ['svm:mirror', '//'], qr'//mv2/m2');

    $svk->copy ('-m', 'copying mirrored path', '//mv2/m2', '//mv2/m-C');
    is_output_like ($svk, 'propget', ['svm:mirror', '//'], qr'//mv2/m-C');

    $svk->copy ('-m', 'copying tree containing mirrored path', '//mv2', '//mv-C');
    is_output_like ($svk, 'propget', ['svm:mirror', '//'], qr'//mv-C/m2');

    SKIP: {
        skip($TODO, 2);

	$svk->remove ('-m', 'removing mirrored path', '//mv2/m2');
	is_output_like ($svk, 'propget', ['svm:mirror', '//'], qr{^(?!.*//mv2/m2)});

	$svk->remove ('-m', 'removing tree containing mirrored path', '//mv-C');
	is_output_like ($svk, 'propget', ['svm:mirror', '//'], qr{^(?!.*//mv-C/m2)});
    }
}
