#!/usr/bin/perl -w
use strict;
use Test::More;
BEGIN { require 't/tree.pl' };
our $output;
# XXX: fixme on win32
if ($^O eq 'MSWin32') {
    plan skip_all => "win32";
    exit;
};
plan tests => 7;

# build another tree to be mirrored ourself
my ($xd, $svk) = build_test('test');
my $tree = create_basic_tree ($xd, '/test/');

my ($repospath, undef, $repos) = $xd->find_repos ('/test/', 1);
my $uuid = $repos->fs->get_uuid;

my $svkupd_pid;
{
    $svkupd_pid = fork();
    unless ( $svkupd_pid ) {
	exec ($^X, '-Ilib', 'bin/svkupd', '--depot', $repospath)
	    or die "$!";
    }
}

my ($copath, $corpath) = get_copath ('svkup');

sleep 1;
run_svkup ($copath, "$uuid:/");
ok (-e "$copath/A/be");
is_file_content ("$copath/me", "first line in me\n2nd line in me - mod\n");

ok (-e "$copath/B/fe");
run_svkup ($copath, "$uuid:/:1");
ok (!-e "$copath/B/fe");
ok (!-e "$copath/D");
ok (-e "$copath/A/P");

run_svkup ($copath);

run_svkup ($copath);

# recheckout base if it's modified.
append_file ("$copath/me", "modified\n");
run_svkup ($copath, "$uuid:/:1");

is_file_content ("$copath/me", "first line in me\n2nd line in me\n");


sub run_svkup {
#    my ($path, $target) = @_;
    system ($^X, '-Ilib', 'bin/svkup', 'localhost', @_);
#    print `$^X -Ilib bin/svkup localhost $path $target`;
}

END {
    kill 15, $svkupd_pid
	if $svkupd_pid;
}
