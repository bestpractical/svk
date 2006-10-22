#!/usr/bin/perl -w
use strict;
use Test::More;
use SVK::Test;
use SVK::Mirror;
use SVK::Mirror::Backend::SVNRa;
plan tests => 9;

my ($xd, $svk) = build_test('test');
my ($copath, $corpath) = get_copath ('api-mirror');

our $output;

my $tree = create_basic_tree ($xd, '/test/');
my ($repospath, $path, $repos) = $xd->find_repos ('//', 1);
my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/', 1);
my $uri = uri($srepospath.($spath eq '/' ? '' : $spath));

my $m = SVK::Mirror->create(
        { repos => $repos, path => '/m', backend => 'SVNRa',
	  url => "$uri/A", pool => SVN::Pool->new } );

is_output($svk, 'pg', ['svm:source', '//m'],
	  [uri($srepospath).'!/A']);

is_output($svk, 'pg', ['svm:uuid', '//m'],
	  [$srepos->fs->get_uuid]);

is_output($svk, 'pg', ['svm:mirror', '//'],
	  ['/m', '' ]);

$m = SVK::Mirror->load(
        { repos => $repos, path => '/m',
	  pool => SVN::Pool->new }
    );

is( $m->url, "$uri/A" );

$m = SVK::Mirror->create(
    {   repos   => $repos,
        path    => '/m2',
        backend => 'SVNRa',
        url     => "$uri/B",
        pool    => SVN::Pool->new
    }
);

is_output($svk, 'pg', ['svm:source', '//m2'],
	  [uri($srepospath).'!/B']);

is_output($svk, 'pg', ['svm:uuid', '//m2'],
	  [$srepos->fs->get_uuid]);

is_output($svk, 'pg', ['svm:mirror', '//'],
	  ['/m', '/m2', '']);

eval {
SVK::Mirror::Backend::SVNRa->create(
    SVK::Mirror->new(
        { repos => $repos, path => '/m3',
	  url => $uri, pool => SVN::Pool->new }
    )
);
};

is($@, "Mirroring overlapping paths not supported\n");

is_output($svk, 'ls', ['//'], ['m/', 'm2/'], 'm3 not created');


$m = SVK::Mirror->load(
        { repos => $repos, path => '/m',
	  pool => SVN::Pool->new }
    );

$m->traverse_new_changesets(sub { diag join(',',@_); });
