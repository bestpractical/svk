package SVK::Mirror;
use strict;
use warnings;

use SVN::Core;

use Sys::Hostname;

use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(repos path server_uuid pool _backend _locked));

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

    SVK::MirrorCatalog->add_mirror($self);

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

    $self->_backend( $self->_load_backend );

    return $self;
}

sub _load_backend {
    my ($self) = @_;

    return SVK::Mirror::Backend::SVNRa->load( { mirror => $self } );
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
    return $self->_find_remote_rev($rev, $self->mirror->repos);
}

sub _find_local_rev {
    my ($self, $rev, $repos) = @_;
    $repos ||= $self->mirror->repos;
    my $fs = $repos->fs;
    my $prop = $fs->revision_prop ($rev, 'svm:headrev') or return;
    my %rev = map {split (':', $_, 2)} $prop =~ m/^.*$/mg;
    return %rev if wantarray;
    return $rev{ $self->server_uuid };

}

=item find_changeset_from_remote($remote_identifier)

=item traverse_new_changesets($code)

calls C<$code> with an opaque object that C<sync_changeset> understands.

=item sync_changeset($changeset)

=item mirror_changesets

=item get_commit_editor

=item url

=cut

for my $delegate
    qw( find_changeset_from_remote sync_changeset traverse_new_changesets mirror_changesets get_commit_editor url )
{
    no strict 'refs';
    *{$delegate} = sub {
        my $self   = shift;
        my $method = $self->_backend->can($delegate);
        unshift @_, $self->_backend;
        goto $method;
    };
}

=back

=cut

1;
