#!/usr/bin/perl -w
use strict;
use SVK::Util qw( is_executable );
BEGIN { require 't/tree.pl' };
{
    local $SIG{__WARN__} = sub { 1 };
    plan skip_all => 'gnupg not found'
        unless (`gpg --version` || '') =~ /GnuPG/;
    plan (skip_all => "Test does not work with BDB") if $ENV{SVNFSTYPE} eq 'bdb';
}
plan_svm tests => 8;
our $output;

$ENV{SVKPGP} = my $gpg = 'gpg --no-default-keyring --keyring t/svk.gpg --secret-keyring t/svk-sec.gpg --default-key svk';

ok (`$gpg --list-keys` =~ '1024D/A50DE110');

my ($xd, $svk) = build_test('test');

is_output_like ($svk, 'verify', [], qr'SYNOPSIS', 'help');

my $tree = create_basic_tree ($xd, '/test/');

my ($srepospath, $spath, $srepos) = $xd->find_repos ('/test/A', 1);

# install pre-revprop-change hook


my $hook = "$srepospath/hooks/pre-revprop-change".($^O eq 'MSWin32' ? '.bat' : '');
open FH, '>', $hook or die "$hook: $!";
print FH "#!$^X\nexit 0\n";
close FH;
chmod (0755, $hook);

my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);

my $uri = uri($srepospath);
$svk->mirror ('//m', $uri.($spath eq '/' ? '' : $spath));
$svk->sync ('//m');

$svk->copy ('-m', 'branch', '//m', '//l');

my ($copath, $corpath) = get_copath ('sign');

$svk->checkout ('//m', $copath);
append_file ("$copath/Q/qu", "modified and should sign\n");
overwrite_file ("$copath/newfile", "sign a new file\n");
$svk->add ("$copath/newfile");
is_output ($svk, 'ci', ['-S', '-m', 'test signature', $copath],
	   ['Commit into mirrored path: merging back directly.',
	    "Merging back to mirror source $uri/A.",
	    'Merge back committed as revision 3.',
	    "Syncing $uri/A",
	    'Retrieving log information from 3 to 3',
	    'Committed revision 5 from revision 3.']);

is_output ($svk, 'pl', ['--revprop', '-r5', '//'],
	   ['Unversioned properties on revision 5:',
	    '  svk:signature',
	    '  svm:headrev',
	    '  svn:author',
	    '  svn:date',
	    '  svn:log',
	   ]);
is_output ($svk, 'pl', ['--revprop', '-r3', '/test/'],
	   ['Unversioned properties on revision 3:',
	    '  svk:signature',
	    '  svn:author',
	    '  svn:date',
	    '  svn:log',
	   ]);

is_output ($svk, 'verify', [3, '/test/'],
	  ['Signature verified.']);
is_output ($svk, 'verify', [5],
	  ['Signature verified.']);
is_output ($svk, 'verify', [4],
	  ['No signature found for change 4 at //.']);

1;
