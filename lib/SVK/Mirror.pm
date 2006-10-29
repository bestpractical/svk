package SVK::Mirror;
use strict;
use warnings;

use SVN::Core;

use Sys::Hostname;
use Scalar::Util 'weaken';

use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(depot path server_uuid source_uuid pool url _backend _locked));

*repos = sub { Carp::cluck unless $_[0]->depot; shift->depot->repos };

use SVK::Mirror::Backend::SVNRa;

## class SVK::Mirror;
## has ($.repos, $.path, $.server_uuid, $.url, $.pool);
## has $!backend handles <find_changeset_from_remote sync_changeset traverse_new_changesets mirror_changesets get_commit_editor>;
## has $!locked

## submethod BUILD($.path, $.repos, :$backend = 'SVNRa', :$.url, :%backend_options) {
##   $!backend = $.load_backend: self;
##   if $.url {
##       $!backend.new: self;
##   }
##   else {
##       $!backend.load: self;
##   }
##   POST {
##     [&&] $.url, $.server_uuid;
##   }
## }

## method load($path, $repos) {
##   $.new(:$path, :$repos);
##}

=head1 NAME

SVK::Mirror - 

=head1 SYNOPSIS

    # setup a new mirror
    my $mirror = SVK::Mirror->create( { backend => 'SVNRa',  url => 'http://server/',
                                        backend_options => {}, repos => $repos, path => '/mirror' } );
    # load existing mirror
    my $existing = SVK::Mirror->load( { path => $path, repos => $repos } );

    $mirror->mirror_changesets();

    $mirror->traverse_changesets( sub { $revs_to_mirror++ } );

=head1 DESCRIPTION

=over

=item create

=cut

sub create {
    my ( $class, $args ) = @_;
    my $self = $class->SUPER::new($args);

    $self->pool( SVN::Pool->new(undef) )
        unless $self->pool;

    $self->_backend(
        $self->_create_backend( $args->{backend}, $args->{backend_options} )
    );

    weaken( $self->{_backend}{mirror} );

    my $t = SVK::Path->real_new( { depot => $self->depot, path => '/' } )
        ->refresh_revision;

    my ($editor) = $t->get_dynamic_editor(
        ignore_mirror => 1,
        caller        => '',
        message       => 'init mirror',
        author        => $ENV{USER},
    );

    my %mirrors = map { ( $_ => 1 ) } $self->path,
        split( /\n/, $t->root->node_prop( '/', 'svm:mirror' ) || '' );

    $editor->change_dir_prop( $editor->_root_baton, 'svm:mirror',
        join( "\n", ( grep length, sort keys %mirrors ), '' ) );
    $editor->close_edit;

    return $self;
}

sub _create_backend {
    my ($self, $backend, $args) = @_;
    die unless $backend eq 'SVNRa';

    # put svm:mirror prop

    # actually initialise the mirror on mirror path
    return SVK::Mirror::Backend::SVNRa->create( $self );

}

=item load

=cut

sub load {
    my ( $class, $args ) = @_;
    my $self = $class->SUPER::new($args);

    $self->_backend( SVK::Mirror::Backend::SVNRa->load( $self ) );
    weaken( $self->{_backend}{mirror} );

    return $self;
}

=back

=head2 METHODS

=over

=item detach

=item relocate($newurl)

=item with_lock($code)

=cut

sub with_lock {
    my ( $self, $lock, $code ) = @_;

    $self->lock;
    $code->();
    $self->unlock;

}

sub _lock_token {
    my $token = $_[0]->path;
    $token =~ s/_/__/g;
    $token =~ s{/}{_}g;
    return "svm:lock:$token";
}

sub _lock {
    my ($self)  = @_;
    my $fs      = $self->repos->fs;
    my $token   = $self->_lock_token;
    my $content = hostname . ':' . $$;
    my $where = join( ' ', ( caller(0) )[ 0 .. 2 ] );

    # This is not good enough but race condition should result in failed sync
    # without corrupting repository.
LOCKED:
    {
        while (1) {
            my $who = $fs->revision_prop( 0, $token ) or last LOCKED;
            print loc( "Waiting for lock on %1: %2.\n", $self->path, $who );
            sleep 1;
        }
    }
    $fs->change_rev_prop( 0, $token, $content );
    $self->_locked(1);
}

sub _unlock {
    my ( $self, $force ) = @_;
    my $fs = $self->repos->fs;
    if ($force) {
        for ( keys %{ $fs->revision_proplist(0) } ) {
            $fs->change_rev_prop( 0, $_, undef );
        }
        return;
    }

    my $token = $self->_lock_token;
    if ( $self->_locked ) {
        $fs->change_rev_prop( 0, $token, undef );
        $self->_locked(0);
    }
}

=item find_changeset($localrev)

Returns an opaque object that C<sync_changeset> understands.

=cut

sub find_changeset {
    my ($self, $rev) = @_;
    return $self->_find_remote_rev($rev, $self->repos);
}

sub _find_remote_rev {
    my ($self, $rev, $repos) = @_;
    $repos ||= $self->repos;
    my $fs = $repos->fs;
    my $prop = $fs->revision_prop($rev, 'svm:headrev') or return;
    my %rev = map {split (':', $_, 2)} $prop =~ m/^.*$/mg;
    return %rev if wantarray;
    return $rev{ $self->server_uuid };

}

=item find_rev_from_changeset($remote_identifier)

=item traverse_new_changesets($code)

calls C<$code> with an opaque object and metadata that C<sync_changeset> understands.

=item sync_changeset($changeset, $metadata)

=item mirror_changesets

=item get_commit_editor

=item url

=cut

for my $delegate
    qw( find_rev_from_changeset sync_changeset traverse_new_changesets mirror_changesets get_commit_editor )
{
    no strict 'refs';
    *{$delegate} = sub {
        my $self   = shift;
        my $method = $self->_backend->can($delegate);
        unshift @_, $self->_backend;
        goto $method;
    };
}

# TMP method to be compat with SVK::MirrorCatalog::Entry

sub spec {
    my $self = shift;
    return join(':', $self->server_uuid, $self->_backend->source_path);
}

sub find_local_rev {
    my ($self, $changeset) = @_;
    $self->find_rev_from_changeset($changeset);
}

=back

=cut

1;
