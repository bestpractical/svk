#!/usr/bin/perl -w
use strict;
BEGIN { require 't/tree.pl' };
use POSIX qw(setlocale LC_CTYPE);
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'zh_TW.Big5')
    or plan skip_all => 'cannot set locale to zh_TW.Big5';
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'en_US.UTF-8')
    or plan skip_all => 'cannot set locale to en_US.UTF-8';;

plan tests => 5;
our ($answer, $output);

my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('i18n');

my $tree = create_basic_tree ($xd, '//');

$svk->co ('//', $copath);

append_file ("$copath/A/Q/qu", "some changes\n");

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
	    "Can't decode commit message as UTF-8, try --encoding."]);
is_output ($svk, 'commit', [$copath, '--encoding', 'big5'],
	   ['Waiting for editor...',
	    'Committed revision 4.']);
$svk->up ($copath);
is_output_like ($svk, 'log', [-r4 => $copath],
		qr/\Q$msgutf8\E/);

setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'zh_TW.Big5') or die "can't setlocale";
is_output_like ($svk, 'log', [-r4 => $copath],
		qr/\Q$msg\E/);
overwrite_file ("$copath/$msg", "with big5 filename\n");
$svk->add ("$copath/$msg");

# reset
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'en_US.UTF-8');
