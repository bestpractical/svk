package SVK::Mirror;
use strict;
use warnings;

use SVN::Core;

use Sys::Hostname;
use SVK::I18N;
use Scalar::Util 'weaken';

use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(depot path server_uuid source_uuid pool url _backend _locked));

*repos = sub { Carp::cluck unless $_[0]->depot; shift->depot->repos };

use SVK::Mirror::Backend::SVNRa;

## class SVK::Mirror;
## has ($.repos, $.path, $.server_uuid, $.url, $.pool);
## has $!backend handles <find_changeset sync_changeset traverse_new_changesets mirror_changesets get_commit_editor>;
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

    $self->{url} =~ s{/+$}{}g;

    $self->pool( SVN::Pool->new(undef) )
        unless $self->pool;

    if ( $self->path eq '/' ) {
        $self->_backend(
            $self->_create_backend( 'SVNSync',
                $args->{backend_options} )
        );
        weaken( $self->{_backend}{mirror} );
        return $self;
    }

    my $t = $self->get_svkpath('/');

    my ($editor, %opt) = $t->get_dynamic_editor(
        ignore_mirror => 1,
        message       => loc('Mirror initialized for %1', $self->url),
        author        => $ENV{USER},
    );

    $self->_backend(
        $self->_create_backend( $args->{backend}, $args->{backend_options}, $opt{txn}, $editor )
    );

    weaken( $self->{_backend}{mirror} );

    my %mirrors = map { ( $_ => 1 ) } $self->path,
        split( /\n/, $t->root->node_prop( '/', 'svm:mirror' ) || '' );

    $editor->change_dir_prop( $editor->_root_baton, 'svm:mirror',
        join( "\n", ( grep length, sort keys %mirrors ), '' ) );
    $editor->close_edit;

    return $self;
}

sub _create_backend {
    my $self = shift;
    my ($backend) = @_;
    my $class = 'SVK::Mirror::Backend::'.$backend;
    use UNIVERSAL::require;
    $class->require or die $!;

    # actually initialise the mirror on mirror path
    return $class->create( $self, @_ );

}

=item load

=cut

sub load {
    my ( $class, $args ) = @_;
    my $self = $class->SUPER::new($args);

    my $backend = $self->path eq '/' ? 'SVNSync' : 'SVNRa';
    $self->_backend(
        $self->_load_backend( $backend, $args->{backend_options} ) );
    weaken( $self->{_backend}{mirror} );

    return $self;
}

sub _load_backend {
    my $self = shift;
    my ($backend) = @_;
    my $class = 'SVK::Mirror::Backend::'.$backend;
    use UNIVERSAL::require;
    $class->require or die $!;

    # actually initialise the mirror on mirror path
    return $class->load( $self, @_ );
}

=back

=head2 METHODS

=over

=item detach

=cut

sub detach {
    my ($self, $remove_props) = @_;

    my $t = $self->get_svkpath('/');

    my ($editor) = $t->get_dynamic_editor(
        ignore_mirror => 1,
        message       => 'Discard mirror for '.$self->path,
        author        => $ENV{USER},
    );

    my %mirrors = map { ( $_ => 1 ) } $self->path,
        split( /\n/, $t->root->node_prop( '/', 'svm:mirror' ) || '' );

    $editor->change_dir_prop( $editor->_root_baton, 'svm:mirror',
        join( "\n", grep { $_ ne $self->path }( grep length, sort keys %mirrors ), '' ) );

    if (0 && $remove_props) {
	$editor->change_dir_prop( 0, 'svm:uuid', undef);
	$editor->change_dir_prop( 0, 'svm:source', undef);
	$editor->adjust;
    }

    $editor->close_edit;
}

=item relocate($newurl)

=item with_lock($code)

=cut

sub with_lock {
    my ( $self, $lock, $code ) = @_;

    $self->lock;
    eval { $code->() };
    $self->unlock;
    die $@ if $@;
}

sub _lock_token {
    my $token = $_[0]->path;
    $token =~ s/_/__/g;
    $token =~ s{/}{_}g;
    return "svm:lock:$token";
}

sub lock {
    my ($self)  = @_;
    my $fs      = $self->repos->fs;
    my $token   = $self->_lock_token;
    my $content = hostname . ':' . $$;
    my $where = join( ' ', ( caller(0) )[ 0 .. 2 ] );

    my $lock_message = $self->_lock_message;
    # This is not good enough but race condition should result in failed sync
    # without corrupting repository.
LOCKED:
    {
        while (1) {
            my $who = $fs->revision_prop( 0, $token ) or last LOCKED;
	    $lock_message->($self, $who);
            sleep 1;
        }
    }
    $fs->change_rev_prop( 0, $token, $content );
    $self->_locked(1);
}

sub unlock {
    my ( $self, $force ) = @_;
    my $fs = $self->repos->fs;
    if ($force) {
        for ( keys %{ $fs->revision_proplist(0) } ) {
            next unless m/^svm:lock:/;
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
    # XXX: needs to be more specific
    return $rev{ $self->source_uuid } || $rev{ $self->server_uuid };
}

=item find_rev_from_changeset($remote_identifier)

=item traverse_new_changesets($code)

calls C<$code> with an opaque object and metadata that C<sync_changeset> understands.

=item sync_changeset($changeset, $metadata)

=item mirror_changesets

=item get_commit_editor

=item url

=cut

sub get_svkpath {
    my ($self, $path) = @_;
    return SVK::Path->real_new( { depot => $self->depot, path => $path || $self->path } )
      ->refresh_revision;
}

for my $delegate
    qw( find_rev_from_changeset sync_changeset traverse_new_changesets mirror_changesets get_commit_editor refresh change_rev_prop fromrev source_path relocate )
{
    no strict 'refs';
    *{$delegate} = sub {
        my $self   = shift;
        my $method = $self->_backend->can($delegate);
        unshift @_, $self->_backend;
        goto $method;
    };
}

# compat methods

sub spec {
    my $self = shift;
    return join(':', $self->server_uuid, $self->_backend->source_path);
}

sub find_local_rev {
    my ($self, $changeset, $uuid) = @_;
    $self->find_rev_from_changeset($changeset, $uuid);
}

sub find_remote_rev {
    goto \&find_changeset;
}

sub get_merge_back_editor {
    my $self = shift;
    return ($self->_backend->fromrev, $self->get_commit_editor(@_));
}

sub run {
    my ($self, $torev) = @_;
    return $self->run_svnmirror_sync({ torev => $torev }) unless $self->_backend->has_replay;

    print loc("Syncing %1", $self->url).($self->_backend->_relayed ? loc(" via %1\n", $self->server_url) : "\n");

    $self->mirror_changesets($torev,
        sub {
            my ( $changeset, $rev ) = @_;
            print "Committed revision $rev from revision $changeset.\n";
        }
    );
    die $@ if $@;
}

sub sync_snapshot {
    my ($self, $snapshot) = @_;
    print loc("
svk is now taking a snapshot of the repository at:
  %1

This is essentially making a checkout of the url, and is bad if the
url contains directories like trunk and branches.  If this isn't what
you mean, please hit ^C.

", $self->url);

    $self->run_svnmirror_sync( { skip_to => $snapshot });
}

sub _lock_message {
    my $self = shift;
    my $target = $self->get_svkpath;
    my $i = 0;
    sub {
	my ($mirror, $who) = @_;
	print loc("Waiting for lock on %1: %2.\n", $target->depotpath, $who);
	if (++$i % 3 == 0) {
	    print loc ("
The mirror is currently locked. This might be because the mirror is
in the middle of a sensitive operation or because a process holding
the lock hung or died.  To check if the mirror lock is stalled,  see
if $who is a running, valid process

If the mirror lock is stalled, please interrupt this process and run:
    svk mirror --unlock %1
", $target->depotpath);
	}
    }
}

sub _copy_notify {
    my ($self, $target, $m, undef, $path, $from_path, $from_rev) = @_;
    # XXX: on anchor, try to get a external copy cache
    return unless $m->path ne $path;
    return $target->depot->find_local_mirror($m->server_uuid, $from_path, $from_rev);
}

sub run_svnmirror_sync {
    my ( $self, $arg ) = @_;

    require SVN::Mirror;
    my $target = $self->get_svkpath;

    my $lock_message = $self->_lock_message;
    my $svm = SVN::Mirror->new(
        target_path    => $self->path,
        repos          => $self->depot->repos,
        config         => SVK::Config->svnconfig,
        revprop        => $self->depot->mirror->revprop,
        cb_copy_notify =>
          sub { $self->_copy_notify( $target, $self, @_ ) },
        lock_message => sub { $lock_message->($_[0], $_[2])},
        get_source   => 1,
        pool         => SVN::Pool->new,
        %$arg
    );
    $svm->init;

    $svm->run( $arg->{torev} );
}

=back

=cut

1;
