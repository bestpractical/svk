use Test::More tests => 4;
use strict;
use SVK::Test;
our($output, $answer);
my ($xd, $svk) = build_test();
$svk->mkdir ('-m', 'init', '//V');
my $tree = create_basic_tree ($xd, '//V');
my ($copath, $corpath) = get_copath ('commit-local-file-to-add');
mkdir($copath);
chdir($copath);
is_output ($svk, 'checkout', ['//V/A'],
	   ["Syncing //V/A(/V/A) in ".__"$corpath/A to 3.",
	    'A   A/Q',
	    'A   A/Q/qu',
	    'A   A/Q/qz',
	    'A   A/be']);

ok (-e 'A/Q/qu');

overwrite_file("A/boo", "new file\n");
append_file("A/Q/qu", "to have commit work\n");
append_file("A/Q/qz", "to have commit work\n");

chdir('A');
is_output($svk, 'status', [],
	  ['M   Q/qu',
	   'M   Q/qz',
	   '?   boo']);

sub set_editor_add
{
set_editor(<< 'TMP');
$_ = shift;
open _ or die $!;
@_ = <_>;
# simulate some editing, for --template test
s/^\?/A/g for @_;
close _;
unlink $_;
open _, '>', $_ or die $!;
print _ @_;
close _;
print @_;
TMP
}


set_editor_add();
is_output($svk, 'commit',[],
	  ['Waiting for editor...',
	   'A   boo',
	   'Committed revision 4.']);

