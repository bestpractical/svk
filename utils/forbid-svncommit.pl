#!/usr/bin/perl -w
use strict;
use SVN::Hook;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

use Cwd 'abs_path';
my $repospath = shift or die "repospath required.\n";
$repospath = abs_path($repospath);

my $repos = SVN::Repos::open($repospath) or die "Can't open repository: $@";

my $fs = $repos->fs;
$fs->change_rev_prop(0, 'svk:notify-commit' => '*');

my $hooks = SVN::Hook->new({ repospath => $repospath});

eval { $hooks->init('pre-commit') } or warn $@;

my $forbid = $hooks->hook_path("_pre-commit") . '/forbid-svn-commit';
unlink $forbid if -e $forbid;
$hooks->_install_perl_hook( $forbid, <<'END' );
use strict;
use SVK::XD;
use SVK::Mirror;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

my ($repospath, $txnname) = @ARGV;
die "repospath required" unless $repospath;

my $repos = SVN::Repos::open($repospath) or die "Can't open repository: $@";

my $fs = $repos->fs;
my $txn = $fs->open_txn($txnname) or die 'no such txn';
if ($txn->prop('svk:commit')) {
    $txn->change_prop('svk:commit', undef);
    exit 0;
}

my $depot = SVK::Depot->new( { repos => $repos, repospath => $repos->path, depotname => '' } );
my $changed = $txn->root->paths_changed;
# things that can be improved:
# 1. if A/B is not under mirror, we can skip everything matches A/B/*
# 2. use mirror list check instea of $t->is_mirrored check
for (keys %$changed) {
    my $t = SVK::Path->real_new( {
            depot => $depot,
            path => $_
        }
    )->refresh_revision;

    my $mirror = $t->is_mirrored or next;

    die "change to $_ is under svk mirror: ".$mirror->path."\n";
}

exit 0;
END

print $_->path."\n" for ($hooks->scripts('pre-commit'));
