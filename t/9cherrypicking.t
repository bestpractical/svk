#!/usr/bin/perl
use Test::More tests => 1;
use strict;
no warnings 'once';
require 't/tree.pl';

$svk::info = build_test();
my ($copath, $corpath) = get_copath ('cherrypicking');

svk::checkout ('//', $copath);
mkdir "$copath/trunk";
overwrite_file ("$copath/trunk/foo", "foobar\n");
overwrite_file ("$copath/trunk/test.pl", "foobarbazzz\n");
svk::add ("$copath/trunk");
svk::commit ('-m', 'init', "$copath");

overwrite_file ("$copath/trunk/test.pl", q|#!/usr/bin/perl

sub main {
    print "this is main()\n";
#test
}

|);

svk::commit ('-m', 'change on trunk', "$copath");

append_file ("$copath/trunk/test.pl", q|
sub test {
    print "this is test()\n";
}

|);

svk::commit ('-m', 'more change on trunk', "$copath");

append_file ("$copath/trunk/test.pl", q|
END {
}

|);

svk::commit ('-m', 'more change on trunk', "$copath");

svk::propset ('someprop', 'propvalue', "$copath/trunk/test.pl");
svk::status ($copath);
svk::commit ('-m', 'and some prop', "$copath");

svk::copy ('-m', 'branch //work', '//trunk', '//work');
svk::update ($copath);

`$^X -pi -e 's/is main/is local main/' $copath/work/test.pl`;

svk::commit ('-m', 'local mod', "$copath/work");

append_file ("$copath/trunk/test.pl", q|

# copyright etc
|);

svk::commit ('-m', 'more mod on trunk', "$copath/trunk");

svk::smerge ('-m', 'mergeback from //work', '//work', '//trunk');

svk::smerge ('-m', 'mergeback from //trunk', '//trunk', '//work');

svk::update ($copath);

`$^X -pi -e 's|#!/usr/bin/|#!env |' $copath/trunk/test.pl`;

svk::commit ('-m', 'mod on trunk before branch to featre', "$copath/trunk");

svk::copy ('-m', 'branch //feature', '//trunk', '//feature');
svk::update ($copath);

`$^X -pi -e 's/^#test/    test();/' $copath/work/test.pl`;

svk::commit ('-m', 'call test() in main', "$copath/work");

append_file ("$copath/feature/test.pl", q|

sub newfeature {}

|);

svk::commit ('-m', 'some new feature', "$copath/feature");

`$^X -pi -e 's/newfeature/newnewfeature/' $copath/feature/test.pl`;

svk::commit ('-m', 'rename feature depends on c14', "$copath/feature");
append_file ("$copath/feature/test.pl", q|

sub fnord {}
|);

svk::commit ('-m', 'more features unreleated to c14', "$copath/feature");

svk::cmerge ('-m', 'merge change 14,16 from feature to work', '-c', '14,16', '//feature', '//work');

svk::update ("$copath/work");

ok (1);
