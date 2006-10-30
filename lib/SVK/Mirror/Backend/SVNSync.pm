package SVK::Mirror::Backend::SVNSync;
use strict;
use base 'SVK::Mirror::Backend::SVNRa';

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

    $self->source_root( $mirror->url );
    $self->source_path('');

    return $self;
}

sub _init_state {
    my ( $self, $txn, $editor ) = @_;
    my $mirror = $self->mirror;
    die loc( "Must replicate whole repository at %1.\n", $mirror->url )
        if $self->source_path;

    # XXX: die on existing state
    my $fs = $mirror->depot->repos->fs;
    $fs->change_rev_prop( 0, 'svn:svnsync:from-url',  $mirror->url );
    $fs->change_rev_prop( 0, 'svn:svnsync:from-uuid', $mirror->server_uuid );

    #    $fs->change_rev_prop(0, 'svn:svnsync:last-merged-rev', 0);
    return $self;
}

sub find_rev_from_changeset {
    return $_[0];
}

sub sync_changeset {
    my ( $self, $changeset, $metadata, $callback ) = @_;
    my $t = SVK::Path->real_new(
        { depot => $self->mirror->depot, path => '/' } )->refresh_revision;
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
