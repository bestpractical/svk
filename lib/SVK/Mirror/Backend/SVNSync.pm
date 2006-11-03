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
    die loc("Requires newer svn for replay support when mirroring to /.\n")
	unless $self->has_replay;
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

sub _relayed { }

1;
