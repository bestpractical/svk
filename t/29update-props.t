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
    TODO: {
    local $TODO = "prop conflict should be stated as prop conflict";
    is_output($svk, 'st', [$copath], [
        " C  t/checkout/smerge/me",
    ] );
    }
    TODO: {
    local $TODO = "we don't have interactive prop resolver";
    # don't remember exact markup for conflicts but should be something like:
    is_output($svk, 'di', [$copath], [
        "",
        "Property changes on: $copath/me",
        "___________________________________________________________________",
        "Name: prop",
        " +<<< NEW",
        " +another-value",
        " +=== BASE",
        " +=== OLD",
        " +value",
        " +>>>",
        "",
    ] );
    }
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
