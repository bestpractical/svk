#!/usr/bin/perl -w
use strict;
use Test::More;
use SVK::Test;
use SVK::Mirror;
use SVK::Mirror::Backend::SVNRa;
plan tests => 2;

my ($xd, $svk) = build_test('test');
my ($copath, $corpath) = get_copath ('api-mirror');

our $output;

my $tree = create_basic_tree ($xd, '/test/');
my ($repospath, $path, $repos) = $xd->find_repos ('//', 1);
my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/', 1);
my $uri = uri($srepospath.($spath eq '/' ? '' : $spath));

SVK::Mirror::Backend::SVNRa->create(
    SVK::Mirror->new(
        { repos => $repos, path => '/m',
	  url => $uri, pool => SVN::Pool->new }
    )
);

is_output($svk, 'pg', ['svm:source', '//m'],
	  [$uri.'!']);

is_output($svk, 'pg', ['svm:uuid', '//m'],
	  [$srepos->fs->get_uuid]);

exit;
# XXX: die
SVK::Mirror::Backend::SVNRa->create(
    SVK::Mirror->new(
        { repos => $repos, path => '/m2',
	  url => $uri, pool => SVN::Pool->new }
    )
);


# XXX: die
SVK::Mirror::Backend::SVNRa->create(
    SVK::Mirror->new(
        { repos => $repos, path => '/m2',
	  url => $uri, pool => SVN::Pool->new }
    )
);
