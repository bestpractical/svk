#!/usr/bin/perl -w

use strict;

use Test::More tests => 21;
use File::Path;
use Cwd;
use SVK::Test;

my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('smerge');
my (undef, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;

$svk->mkdir ('-m', 'trunk', '//trunk');
my $tree = create_basic_tree ($xd, '//trunk');
$svk->ps ('-m', 'set prop', 'prop', 'value', '//trunk/me');
$svk->co ('//trunk', $copath);

flush_co();

# the same prop in outdated checkout
{
    $svk->ps ('prop', 'value', "$copath/me");
    is_output($svk, 'up', ['-C', $copath], [
        "Syncing //trunk(/trunk) in $corpath to 4.",
        " g  t/checkout/smerge/me",
    ] );
    is_output($svk, 'up', [$copath], [
        "Syncing //trunk(/trunk) in $corpath to 4.",
        " g  t/checkout/smerge/me",
    ] );
    is_output($svk, 'st', [$copath], [
    ] );
    is_output($svk, 'di', [$copath], [
    ] );
}

flush_co();

# different prop in outdated checkout
{
    $svk->ps ('another-prop', 'value', "$copath/me");
    is_output($svk, 'up', ['-C', $copath], [
        "Syncing //trunk(/trunk) in $corpath to 4.",
        " U  t/checkout/smerge/me",
    ] );
    is_output($svk, 'up', [$copath], [
        "Syncing //trunk(/trunk) in $corpath to 4.",
        " U  t/checkout/smerge/me",
    ] );
    is_output($svk, 'st', [$copath], [
        " M  t/checkout/smerge/me",
    ] );
    is_output($svk, 'di', [$copath], [
        "",
        "Property changes on: $copath/me",
        "___________________________________________________________________",
        "Name: another-prop",
        " +value",
        "",
    ] );
}

flush_co();

# conflict on update
{
    $svk->ps ('prop', 'another-value', "$copath/me");
    is_output($svk, 'up', ['-C', $copath], [
        "Syncing //trunk(/trunk) in $corpath to 4.",
        " C  t/checkout/smerge/me",
        "1 conflict found.",
    ] );
    is_output($svk, 'up', [$copath], [
        "Syncing //trunk(/trunk) in $corpath to 4.",
        " C  t/checkout/smerge/me",
        "1 conflict found.",
    ] );
    is_output($svk, 'st', [$copath], [
        " C  t/checkout/smerge/me",
    ] );

    # XXX: this looks wierd a littl without line endings
    is_output($svk, 'di', [$copath], [
        "",
        "Property changes on: $copath/me",
        "___________________________________________________________________",
        "Name: prop",
        " -value",
        qr" \+>>>> YOUR VERSION Property prop of me \(/trunk\) \d+",
        qr" \+another-value==== ORIGINAL VERSION Property prop of me \d+",
        qr" \+==== THEIR VERSION Property prop of me \(/trunk\) \d+",
        qr" \+value<<<< \d+",
        " +",
        "",
    ] );
}

# flush to required state: revert, update to revision before propset on //trunk
sub flush_co {
    $svk->revert('-R', $copath);
    $svk->up('-r3', $copath);
    is_output($svk, 'up', ['-C', $copath], [
        #XXX, TODO: why it's corpath instead copath?
        "Syncing //trunk(/trunk) in $corpath to 4.",
        " U  t/checkout/smerge/me",
    ] );
    is_output($svk, 'st', [$copath], [
    ] );
    is_output($svk, 'di', [$copath], [
    ] );
}
