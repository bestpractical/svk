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
    my $self = $class->SUPER::new( { mirror => $mirror, use_pipeline => 1 } );
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

sub find_rev_from_changeset { $_[0] }

sub _revmap_prop { }

sub _get_sync_editor {
    my ($self, $editor, $target) = @_;
    return SVK::Editor::CopyHandler->new(
        _editor => $editor,
        cb_copy => sub {
            my ( $editor, $path, $rev ) = @_;
            return ( $path, $rev ) if $rev == -1;
            $path =~ s{^\Q/}{};
            return $target->as_url( 1, $path, $rev );
        }
    )
}

sub _after_replay {
    my ($self, $ra, $editor) = @_;
    $editor->close_edit;
}

sub _relayed { }

1;
