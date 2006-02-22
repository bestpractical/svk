#!/usr/bin/perl -w
use Test::More tests => 33;
use strict;
BEGIN { require 't/tree.pl' };
our $output;
my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('add');
my ($repospath, undef, $repos) = $xd->find_repos ('//', 1);
$svk->checkout ('//', $copath);
is_output_like ($svk, 'add', [], qr'SYNOPSIS', 'add - help');
is_output_like ($svk, 'add', ['nonexist'],
		qr'not a checkout path');
chdir ($copath);
mkdir ('A');
mkdir ('A/deep');
overwrite_file ("A/foo", "foobar");
overwrite_file ("A/bar", "foobar");
overwrite_file ("A/deep/baz", "foobar");
overwrite_file ("A/deep/baz~", "foobar");

overwrite_file ("test.txt", "test..\n");
is_output ($svk, 'add', ['test.txt'],
	   ['A   test.txt']);
is_output_like ($svk, 'add', ['Z/bzz'],
		qr'not a checkout path');
is_output ($svk, 'add', ['asdf'],
	   ["Unknown target: asdf."]);
is_output ($svk, 'add', ['A/foo'],
	   [map __($_), 'A   A', 'A   A/foo'], 'add - descendent target only');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['-q', 'A/foo'],
	   [], 'add - quiet');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ["$corpath/A/foo"],
	   [map __($_), "A   $corpath/A", "A   $corpath/A/foo"], 'add - descendent target only - abspath');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['../add/A/foo'],
	   [map __($_), "A   ../add/A", "A   ../add/A/foo"], 'add - descendent target only - relpath');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['A/deep/baz'],
	   [map __($_), 'A   A', 'A   A/deep', 'A   A/deep/baz'],
	   'add - deep descendent target only');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['A'],
	   [map __($_), 'A   A', 'A   A/bar', 'A   A/foo', 'A   A/deep', 'A   A/deep/baz'],
	   'add - anchor');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['A/'],
	   [map __($_), 'A   A', 'A   A/bar', 'A   A/foo', 'A   A/deep', 'A   A/deep/baz'],
	   'add - anchor with trailing slash');
$svk->revert ('-R', '.');

is_output ($svk, 'add', [qw/-N A/],
	   [map __($_), 'A   A'],
	   'add - nonrecursive anchor');

is_output ($svk, 'add', [qw/-N A/],
	   ['A already added.'],
	   'add - nonrecursive anchor already added');
is_output ($svk, 'add', ['-N', 'A/deep'],
	   [map __($_), 'A   A/deep'],
	   'add - nonrecursive, parent added ');
is_output ($svk, 'add', ['A/foo'],
	   [map __($_), 'A   A/foo'],
	   'add - nonrecursive target');
is_output ($svk, 'add', ['A'],
	   [map __($_), 'A   A/bar', 'A   A/deep/baz'],
	   'add - readd');
$svk->revert ('-R', '.');

is_output ($svk, 'add', ['-N', 'A/foo'],
		["Please add the parent directory 'A' first."],
		'add - nonrecursive target only');

overwrite_file ("A/exe", "foobar");
chmod (0755, "A/exe");
TODO: {
local $TODO = 'notify that added file has executable bit';
is_output($svk, 'add', ['A/exe'],
	  [__('A   A'),
	   __('A   A/exe - (bin)')]);
}
$svk->commit ('-m', 'test exe bit');
is_output ($svk, 'add', [qw/-N A/],
	   ['A already under version control.'],
	   'add - nonrecursive, already committed');

is_output ($svk, 'add', ['A'],
	   [map __($_), 'A   A/bar', 'A   A/deep', 'A   A/deep/baz', 'A   A/foo'],
	   'add - readd with committed anchor');
is_output ($svk, 'add', ['-N', 'A/exe'], [],
	   'add - readd with committed file unmodified');
is_output ($svk, 'add', ['A/exe'], [],
	   'add - readd with committed file unmodified');
overwrite_file ("A/exe", "foobarbaz");
is_output ($svk, 'add', ['-N', 'A/exe'],
	   [],
	   'add - readd with committed file modified');

unlink ('A/exe');
$svk->revert ('A/exe');
ok (_x 'A/exe');

mkdir ('A/mime');
overwrite_file ("A/mime/foo.pl", "#!/usr/bin/perl\n");
overwrite_file ("A/mime/foo.jpg", "\xff\xd8\xff\xe0this is jpeg");
overwrite_file ("A/mime/foo.bin", "\x1f\xf0\xff\x01\x00\xffthis is binary");
overwrite_file ("A/mime/foo.html", "<html>");
overwrite_file ("A/mime/foo.txt", "test....");
overwrite_file ("A/mime/foo.c", "/*\tHello World\t*/");

is_output ($svk, 'add', ['A/mime'],
	   [__('A   A/mime'),
	    __('A   A/mime/foo.bin'),
	    __('A   A/mime/foo.c'),
	    __('A   A/mime/foo.html'),
	    __('A   A/mime/foo.jpg'),
	    __('A   A/mime/foo.pl'),
	    __('A   A/mime/foo.txt'),
	   ]);
is_output ($svk, 'pl', ['-v', glob("A/mime/*")],
	   [__('Properties on A/mime/foo.bin:'),
	    '  svn:mime-type: application/octet-stream',
	    __('Properties on A/mime/foo.html:'),
	    '  svn:mime-type: text/html',
	    __('Properties on A/mime/foo.jpg:'),
	    '  svn:mime-type: image/jpeg',
	   ]);


$svk->revert ('-R', 'A');

mkdir ('Ai');
overwrite_file ("Ai/foo", "foobar");
overwrite_file ("Ai/bar", "foobar");
overwrite_file ("Ai/tilde~", "foobar");
$svk->add ('-N', 'Ai');
$svk->propset ('svn:ignore', 'f*', 'Ai');
is_output ($svk, 'add', ['Ai'],
	   [map __($_), 'A   Ai/bar']);
$svk->revert ('-R', 'Ai');

$svk->add ('-N', 'Ai');
$svk->propset ('svn:ignore', 'f*', 'Ai');
is_output ($svk, 'add', ['Ai/foo', 'Ai/tilde~', 'Ai/bar'],
	   [map __($_), 'A   Ai/bar', 'A   Ai/foo', 'A   Ai/tilde~']);
$svk->commit ('-m', 'commit');
is_output ($svk, 'ls', ['//Ai'], ['bar', 'foo', 'tilde~']);

# auto-prop
use File::Temp qw/tempdir/;
my $dir = tempdir ( CLEANUP => 1 );
overwrite_file (File::Spec->catfile ($dir, 'servers'), '');
overwrite_file (File::Spec->catfile ($dir, 'config'), << "EOF");
[miscellany]
enable-auto-props = yes
[auto-props]
*.txt = svn:eol-style=native;svn:keywords=Revision Id
*.pl = svn:eol-style=native;svn:mime-type=text/perl

EOF

$xd->{svnconfig} = SVN::Core::config_get_config ($dir);
mkdir ('A/autoprop');
overwrite_file ("A/autoprop/foo.pl", "#!/usr/bin/perl\n");
overwrite_file ("A/autoprop/foo.txt", "Text file\n");
overwrite_file ("A/autoprop/foo.bar", "this is just a test\n");

# test enumerator
eval { $xd->{svnconfig}{config}->enumerate ('auto-props', sub {}) };

SKIP: {

skip 'svn too old, does not support config enumerator', 2 if $@;

is_output ($svk, 'add', ['A/autoprop'],
	   [__('A   A/autoprop'),
	    __('A   A/autoprop/foo.bar'),
	    __('A   A/autoprop/foo.pl'),
	    __('A   A/autoprop/foo.txt')]);

is_output ($svk, 'pl', ['-v', glob("A/autoprop/*")],
	   [__('Properties on A/autoprop/foo.pl:'),
	    '  svn:eol-style: native',
	    '  svn:mime-type: text/perl',
	    __('Properties on A/autoprop/foo.txt:'),
	    '  svn:eol-style: native',
	    '  svn:keywords: Revision Id'
	   ]);

}

eval { overwrite_file("A/\x{05}file", "fnord\n") };

SKIP: {

skip "can't create file with control character.", 1 unless -e "A/\x{05}file";

is_output ($svk, 'add', ["A/\x{05}file"],
	   [__("Invalid control character '0x05' in path 'A/\x{05}file'")]);


}
