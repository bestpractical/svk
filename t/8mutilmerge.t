#!/usr/bin/perl
use Test::More tests => 1;
use strict;
no warnings 'once';
require 't/tree.pl';

$svk::info = build_test();
my ($copath, $corpath) = get_copath ('multimerge');

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

svk::proplist ('-v', "$copath/work");

svk::smerge ('-m', 'merge from //feature', '//feature', '//work');

svk::update ($copath);

svk::proplist ('-v', "$copath/work");
svk::proplist ('-v', "$copath/feature");

svk::smerge ('-m', 'merge from //work to //trunk', '//work', '//trunk');
svk::smerge ('-m', 'merge from //trunk to //feature', '//trunk', '//feature');

ok (1);

__END__

test plan:

//test/trunk
r1-r5

//test/work
r6 (from trunk:5)

//test/work
r7

//test/trunk
r8

//test/trunk
r9 (merged from work:8)

//test/work
r10 (merged from trunk:9)

//test/trunk
r11

//test/feature
r12 (from trunk:11)

*note that /feature also has the ticket work:8 from copy*

//test/work
r13

//test/feature
r14

//test/work
r15 (merged from feature:14)
<base should be trunk:9>
# auto merge (9, 14) /feature -> /work (base /trunk)

//test/trunk
r16 (merged from work:15)
<ticket: feature:14, work:15>

//test/feature
r17 (merged from trunk:16)
<base should be feature:14>
