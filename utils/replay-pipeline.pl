#!/usr/bin/perl
use strict;
use warnings;


package SVK::Editor::Serialize;
use base 'SVK::Editor';

__PACKAGE__->mk_accessors(qw(cb_serialize_entry));

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = our $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;
    my $baton;
    pop @arg if ref ($arg[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;

    warn "==> starting " if $func eq 'open_root';

    if ((my $baton_at = $self->baton_at ($func)) >= 0) {
	$baton = $arg[$baton_at];
    }
    else {
	$baton = 0;
    }

    my $ret = $func =~ m/^(?:add|open)/ ? ++$self->{batons} : undef;
    Carp::cluck unless defined $func;
    $self->cb_serialize_entry->([$ret, $func, @arg]);
    return $ret;
}

my $apply_textdelta_entry;

sub close_file {
    my ($self, $baton, $checksum) = @_;
    if ($apply_textdelta_entry) {
	$self->cb_serialize_entry->($apply_textdelta_entry);
	$apply_textdelta_entry = undef;
    }
    $self->cb_serialize_entry->([undef, 'close_file', $baton, $checksum]);
}

sub apply_textdelta {
    my ($self, $baton, @arg) = @_;
    pop @arg if ref ($arg[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;
    my $entry = [undef, 'apply_textdelta', $baton, @arg, ''];
    open my ($svndiff), '>', \$entry->[-1];
#    $self->cb_serialize_entry->($entry);
    $apply_textdelta_entry = $entry;
    return [SVN::TxDelta::to_svndiff($svndiff)];
}


1;


package main;

use SVN::Core;
use SVK::XD;

my ($repospath, $path, $from, $to) = @ARGV;
my $repos = SVN::Repos::open($repospath) or die $!;

my $depot = SVK::Depot->new({ depotname => '', repos => $repos });
my $m = SVK::Mirror->load({ path => $path, depot => $depot, pool => SVN::Pool->new });
die unless $m;
die unless $m->_backend->isa('SVK::Mirror::Backend::SVNRa');
my $b = $m->_backend;

my $ra = $b->_new_ra;

my $pool = SVN::Pool->new_default;
my $fh = \*STDOUT;


$fh->blocking(0);

my $current_editors = 0;
my $unsent_buf = '';


my $buf;

my $max;
use YAML::Syck 'Dump';
use IO::Select;
use IO::Handle;
use Storable 'nfreeze';
use POSIX 'EPIPE';

sub on_close_edit {
    warn "close edit";
    --$current_editors;
}


sub try_flush {
    my $wait = shift;
    my $max_write = $wait ? -1 : 10;
    if ($wait) {
	$fh->blocking(1);
    }
    else {
	$fh->blocking(0);
	my $wstate = '';
	vec($wstate,fileno($fh),1) = 1;
	select(undef, $wstate, undef, 0);;
	return unless vec($wstate,fileno($fh),1);

    }
    my $i = 0;
    while ( 
	    $#{$buf} >= 0 || length($unsent_buf) ) {
	if (my $len = length $unsent_buf) {
	    warn "==> dealing with unsetn buf of $len";
	    if (my $ret = syswrite($fh, $unsent_buf)) {
		substr($unsent_buf, 0, $ret, '');
		last if $ret != $len;
	    }
	    else {
		die if $! == EPIPE;
		return;
	    }
	}
	last if $#{$buf} < 0;
	use Carp;
	Carp::cluck unless defined $buf->[0];
	my $msg = nfreeze($buf->[0]);
	$msg = pack('N', length($msg)).$msg;
#	warn "to send ".length($msg);
#	use Digest::MD5 'md5_hex';
#	warn md5_hex($buf->[0][-1]) if $buf->[0][1] eq 'apply_textdelta'; 

	if (my $ret = syswrite($fh, $msg)) {
	    $unsent_buf .= substr($msg, $ret)  if length($msg) != $ret;
	    warn "$ret?!?! ".length($msg) if length($msg) != $ret;
	    on_close_edit() if (shift @$buf)->[1] eq 'close_edit';
	}
	else {
	    die if $! == EPIPE;
	    # XXX: check $! for fatal
	    last;
	}
    }
}

sub entry {
    my $entry = shift;

    push @$buf, $entry;
    try_flush();

}

my $max_editor_in_buf = 5;

for my $rev ($from..$to) {
    $pool->clear;

    while ($current_editors > $max_editor_in_buf) {
	warn "waiting for flush for $rev.. ($current_editors).";

	try_flush(1);
    }

    ++$current_editors;
    warn "replay $rev ($current_editors)";
    $ra->replay($rev, 0, 1,# SVK::Editor->new(_debug=>1));
		SVK::Editor::Serialize->new({ cb_serialize_entry => \&entry }));
    entry([undef, 'close_edit']);
}
while ($#{$buf} >= 0) {
    warn "... $#{$buf}";
    try_flush(1) ;
}

