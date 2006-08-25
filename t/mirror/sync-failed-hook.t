#!/usr/bin/perl -w
use strict;
use Test::More;
BEGIN { require 't/tree.pl' };
eval { require SVN::Mirror; 1 } or plan skip_all => 'require SVN::Mirror';
plan tests => 3;

my ($xd, $svk) = build_test('test');

our $output;

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);
$svk->mkdir ('-m', 'init', '/test/A');

my ($copath, $corpath) = get_copath ('svnhook-svn');

my $uri = uri($srepospath.($spath eq '/' ? '' : $spath));

my ($repospath, $path, $repos) = $xd->find_repos ('//m', 1);
my $muri = uri($repospath.($path eq '/' ? '' : $path));

$svk->mirror('//m', $uri);

is_output($svk, 'sync', ['//m'],
	  ["Syncing $uri",
	   'Retrieving log information from 1 to 1',
	   'Committed revision 2 from revision 1.']);

is_output($svk, 'sync', ['//m'],
	  ["Syncing $uri"]);

{
    open my $fh, '>', "$repospath/hooks/pre-commit" or die $!;
    local $/;
    my $buf = <DATA>;
    $buf =~ s|PERL|$^X|;
    print $fh $buf;
}
chmod 0755, "$repospath/hooks/pre-commit";

skip "Can't run hooks", 1 unless -x "$repospath/hooks/pre-commit";

$svk->mkdir('-m', 'A/X', '/test/A/X');
is_output($svk, 'sync', ['//m'],
	  ["Syncing $uri",
	   'Retrieving log information from 2 to 2',
	   "A repository hook failed: 'pre-commit' hook failed with error output:",
	   'hate']);

__DATA__
#!PERL
print STDERR "hate";
exit -1;
