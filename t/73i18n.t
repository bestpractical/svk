#!/usr/bin/perl -w
use strict;
use File::Path;
BEGIN { require 't/tree.pl' };
use POSIX qw(setlocale LC_CTYPE);
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'zh_TW.Big5')
    or plan skip_all => 'cannot set locale to zh_TW.Big5';
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'en_US.UTF-8')
    or plan skip_all => 'cannot set locale to en_US.UTF-8';;

plan tests => 12;
our ($answer, $output);

my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('i18n');

my $tree = create_basic_tree ($xd, '//');

$svk->checkout ('//A', $copath);

append_file ("$copath/Q/qu", "some changes\n");

my $msg = "\x{ab}\x{eb}"; # Chinese hate in big5
my $msgutf8 = '恨';

set_editor(<< "TMP");
\$_ = shift;
open _ or die \$!;
\@_ = ("I $msg software\n", <_>);
close _;
unlink \$_;
open _, '>', \$_ or die \$!;
print _ \@_;
close _;
TMP
is_output ($svk, 'cp', [-m => $msg, '--encoding', 'big5', '//A' => '//A-cp'],
	   ['Committed revision 3.']);

is_output ($svk, 'commit', [$copath],
	   ['Waiting for editor...',
	    "Can't decode commit message as utf8, try --encoding."]);
is_output ($svk, 'commit', [$copath, '--encoding', 'big5'],
	   ['Waiting for editor...',
	    'Committed revision 4.']);
is_output_like ($svk, 'log', [-r4 => $copath],
		qr/\Q$msgutf8\E/);

is_output ($svk, 'mkdir', [-m => $msg, '--encoding', 'big5', "//A/$msgutf8-dir"],
	   ["Can't decode path as big5-eten, try --encoding."]);
is_output ($svk, 'mkdir', [-m => $msg, '--encoding', 'big5', "//A/$msg-dir"],
	   ['Committed revision 5.']);
$svk->up ($copath);
ok (-e "$copath/$msgutf8-dir");

setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'zh_TW.Big5');
is_output_like ($svk, 'log', [-r4 => '//'],
		qr/\Q$msg\E/);
is_output_like ($svk, 'log', [-vr5 => '//'],
		qr/\Q$msg-dir\E/);

rmtree [$copath];
is_output ($svk, 'checkout', ['//A', $copath],
	   ["Syncing //A(/A) in $corpath to 5.",
	    __"A   $copath/Q",
	    __"A   $copath/Q/qu",
	    __"A   $copath/Q/qz",
	    __"A   $copath/be",
	    __"A   $copath/$msg-dir"], 'checkout reports files in native encoding');

ok (-e "$copath/$msg-dir", 'file checked out in filename of native encoding');
ok (!-e "$copath/$msgutf8-dir", 'not utf8');

overwrite_file ("$copath/$msg", "with big5 filename\n");
$svk->add ("$copath/$msg");

# reset
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'en_US.UTF-8');
