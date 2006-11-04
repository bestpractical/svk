package SVK::Mirror::Backend::SVNSync;
use strict;
use base 'SVK::Mirror::Backend::SVNRa';
use SVK::I18N;

sub _do_load_fromrev {
    my $self = shift;
    return $self->mirror->repos->fs->youngest_rev;
}

sub load {
    my ( $class, $mirror ) = @_;
    my $self = $class->SUPER::new( { mirror => $mirror } );
    my $fs = $mirror->depot->repos->fs;
    $mirror->url( $fs->revision_prop( 0,         'svn:svnsync:from-url' ) );
    $mirror->server_uuid( $fs->revision_prop( 0, 'svn:svnsync:from-uuid' ) );
    $mirror->source_uuid( $fs->revision_prop( 0, 'svn:svnsync:from-uuid' ) );

    die loc("%1 is not a mirrored path.\n", "/".$self->mirror->depot->depotname."/")
	unless $mirror->url;
    $self->source_root( $mirror->url );
    $self->source_path('');

    return $self;
}

sub _init_state {
    my ( $self, $txn, $editor ) = @_;
    die "Requires newer svn for replay support.\n" unless $self->has_replay;
    my $mirror = $self->mirror;
    die loc( "Must replicate whole repository at %1.\n", $mirror->url )
        if $self->source_path;

    my $fs = $mirror->depot->repos->fs;
    if ( my $from = $fs->revision_prop( 0, 'svn:svnsync:from-url' ) ) {
        die loc( "%1 is already a mirror of %2.\n",
            "/" . $mirror->depot->depotname . "/", $from );
    }
    $fs->change_rev_prop( 0, 'svn:svnsync:from-url',  $mirror->url );
    $fs->change_rev_prop( 0, 'svn:svnsync:from-uuid', $mirror->server_uuid );

    #    $fs->change_rev_prop(0, 'svn:svnsync:last-merged-rev', 0);
    return $self;
}

sub _do_relocate {
    my ($self) = @_;
    $self->mirror->depot->reposfs->change_rev_prop( 0, 'svn:svnsync:from-url',  $self->mirror->url );
}

sub find_rev_from_changeset {
    return $_[0];
}

sub sync_changeset {
    my ( $self, $changeset, $metadata, $callback ) = @_;
    my $t = $self->mirror->get_svkpath('/');
    my ( $editor, undef, %opt ) = $t->get_editor(
        ignore_mirror => 1,
        message       => $metadata->{message},
        author        => $metadata->{author},
        callback      => sub {
            $t->repos->fs->change_rev_prop( $_[0], 'svn:date',
                $metadata->{date} );
            $self->fromrev( $_[0] );
            $callback->( $changeset, $_[0] ) if $callback;
        }
    );

    my $ra = $self->_new_ra;
    my $pool = SVN::Pool->new_default;
    if ( my $revprop = $self->mirror->depot->mirror->revprop ) {
        my $prop = $ra->rev_proplist($changeset);
        for (@$revprop) {
            $opt{txn}->change_prop( $_, $prop->{$_} )
                if exists $prop->{$_};
        }
    }

    $editor = SVK::Editor::CopyHandler->new(
        _editor => $editor,
        cb_copy => sub {
            my ( $editor, $path, $rev ) = @_;
            return ( $path, $rev ) if $rev == -1;
            $path =~ s{^\Q/}{};
            return $t->as_url( 1, $path, $rev );
        }
    );

    $ra->replay( $changeset, 0, 1, $editor );
    $self->_ra_finished($ra);
    $editor->close_edit;
    return;

}

=item mirror_changesets

=cut

sub get_pipeline_editor_fh {
    my ($self, $gen) = @_;
    my $ra = $self->_new_ra;

    return SVK::Mirror::Backend::SVNSync::Async->new($self, $ra, $gen);
}

sub mirror_changesets {
    my ( $self, $torev, $callback ) = @_;
    $self->mirror->with_lock( 'mirror',
        sub {
	    $self->refresh;
	    my $from = ($self->fromrev || 0)+1;
	    my $ra = $self->_new_ra;
	    $torev ||= $ra->get_latest_revnum;
	    $self->_ra_finished($ra);
	    my @revs = ($from..$torev);
	    my $fh = $self->get_pipeline_editor_fh(sub { shift @revs });
            $self->traverse_new_changesets(
                sub { $self->evil_sync_changeset( @_, $fh, $callback ) }, $torev );
        }
    );
}

use Digest::MD5 'md5_hex';
sub emit {
    my ($self, $editor, $func, $pool, @arg) = @_;
    my ($ret, $baton_at);
    if ($func eq 'apply_textdelta') {
	my $svndiff = pop @arg;
	$ret = $editor->apply_textdelta(@arg, $pool);
	if ($ret && $#$ret > 0) {
	    my $stream = SVN::TxDelta::parse_svndiff(@$ret, 1, $pool);
	    print $stream $svndiff;
	    close $stream;
	}
    }
    else {
	$ret = $editor->$func(@arg, $pool);
    }
    return $ret;
}

use Storable 'thaw';

sub read_msg {
    my ($sock) = @_;
    my ($len, $msg);
    read $sock, $len, 4 or die $!;
    $len = unpack ('N', $len);
    my $rlen = read $sock, $msg, $len or die $!;
    return \$msg;
}

my $baton_map = {};
my $baton_pool = {};

sub _read_evil_replay {
    my ($self, $editor, $fh) = @_;
    my $pool;
    while (my $data = read_msg($fh)) {
	my $x = thaw($$data);
	my ($next, $func, @arg) = @$x;
	my $baton_at = SVK::Editor->baton_at($func);
	my $baton = $arg[$baton_at];
	if ($baton_at >= 0) {
	    $arg[$baton_at] = $baton_map->{$baton};
	}

	my $ret = $self->emit($editor, $func, $pool, @arg);

	last if $func eq 'close_edit';

	if ($func =~ m/^close/) {
	    Carp::cluck $func unless $baton_map->{$baton};
	    delete $baton_map->{$baton};
	    delete $baton_pool->{$baton};
	}

	if ($next) {
	    $baton_pool->{$next} = SVN::Pool->new_default;
	    $baton_map->{$next} = $ret
	}
    }
}

sub evil_sync_changeset {
    my ( $self, $changeset, $metadata, $fh, $callback ) = @_;
    my $t = $self->mirror->get_svkpath('/');
    my ( $editor, undef, %opt ) = $t->get_editor(
        ignore_mirror => 1,
        message       => $metadata->{message},
        author        => $metadata->{author},
        callback      => sub {
            $t->repos->fs->change_rev_prop( $_[0], 'svn:date',
                $metadata->{date} );
            $self->fromrev( $_[0] );
            $callback->( $changeset, $_[0] ) if $callback;
        }
    );

    my $ra = $self->_new_ra;
    my $pool = SVN::Pool->new_default;
    if ( my $revprop = $self->mirror->depot->mirror->revprop ) {
        my $prop = $ra->rev_proplist($changeset);
        for (@$revprop) {
            $opt{txn}->change_prop( $_, $prop->{$_} )
                if exists $prop->{$_};
        }
    }

    $editor = SVK::Editor::CopyHandler->new(
        _editor => $editor,
        cb_copy => sub {
            my ( $editor, $path, $rev ) = @_;
            return ( $path, $rev ) if $rev == -1;
            $path =~ s{^\Q/}{};
            return $t->as_url( 1, $path, $rev );
        }
    );

    $self->_read_evil_replay($editor, $fh);
    $self->_ra_finished($ra);
    return;

}

sub _relayed { }

package SVK::Mirror::Backend::SVNSync::Async;
use SVK::Editor::Serialize;
use Socket;

my $max_editor_in_buf = 5;
my $current_editors = 0;
my $unsent_buf = '';

my $buf;
my $max;

use IO::Handle;
use Storable 'nfreeze';
use POSIX 'EPIPE';

sub on_close_edit {
    --$current_editors;
}

sub try_flush {
    my $fh = shift;
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

	if (my $ret = syswrite($fh, $msg)) {
	    $unsent_buf .= substr($msg, $ret)  if length($msg) != $ret;
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
}

sub new {
    my ($self, $svnsync, $ra, $gen) = @_;
    socketpair(my $c, my $p, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
	or  die "socketpair: $!";

    if (my $pid = fork) {
	close $p;
	return $c;
    }
    else {
	die "cannot fork: $!" unless defined $pid;
	close $c;
    }

    my $pool = SVN::Pool->new_default;
    while (my $changeset = $gen->()) {
	$pool->clear;
	while ($current_editors > $max_editor_in_buf) {
	    warn "waiting for flush for $changeset.. ($current_editors).";
	    try_flush($p, 1);
	}

	++$current_editors;
	warn "replay $changeset ($current_editors)";
	$ra->replay($changeset, 0, 1,# SVK::Editor->new(_debug=>1));
		    SVK::Editor::Serialize->new({ cb_serialize_entry =>
						  sub { entry(@_); try_flush($p) } }));
	entry([undef, 'close_edit']);
	try_flush($p);
    }

    while ($#{$buf} >= 0) {
	try_flush($p, 1) ;
    }
    exit;
}



1;
