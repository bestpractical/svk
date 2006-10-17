package SVK::Mirror::Backend::SVNRa;
use strict;
use warnings;

# We'll extract SVK::Mirror::Backend later.
# use base 'SVK::Mirror::Backend';
use base 'Class::Accessor::Fast';

# for this: things without _'s will probably move to base
# SVK::Mirror::Backend
__PACKAGE__->mk_accessors(qw(mirror url _config _auth_baton _auth_ref _auth_baton _pool));

=head1 NAME

SVK::Mirror::Backend::SVNRa - 

=head1 SYNOPSIS


=head1 DESCRIPTION

=over

=item load

=cut

sub load {
    my ( $class, $args ) = @_;
    my $self = $class->SUPER::new($args);


    return $self;
}

=item create

=cut

sub create {
    my ($class, $mirror) = @_;
    # init the svm:source and svm:uuid thing on $mirror->path
    # note that the ->source is splitted with '!' and put into source_root and source_path (or something)
}

sub _new_ra {
    my ($self) = @_;

    $self->_initialize_svn;

    return SVN::Ra->new( url => $self->url,
                         auth => $self->_auth_baton,
                         config => $self->_config );
}

sub _initialize_svn {
    my ($self) = @_;

    $self->_pool( SVN::Pool::create )
    $self->_config( SVN::Core::config_get_config(undef, $self->_pool) )
      unless $self->_config;
    $self->_initialize_auth
      unless $self->_auth_baton;
}

sub _initalize_auth {
    my ($self) = @_;

    # create a subpool that is not automatically destroyed
    my $auth_pool = SVN::Pool::create (${ $self->mirror->pool });
    $auth_pool->default;

    my ($baton, $ref) = SVN::Core::auth_open_helper([
        SVN::Client::get_simple_provider (),
        SVN::Client::get_ssl_server_trust_file_provider (),
        SVN::Client::get_username_provider (),
        SVN::Client::get_simple_prompt_provider( $self->can('_simple_prompt'), 2),
        SVN::Client::get_ssl_server_trust_prompt_provider( $self->can('_ssl_server_trust_prompt') ),
        SVN::Client::get_ssl_client_cert_prompt_provider( $self->can('_ssl_client_cert_prompt'), 2 ),
        SVN::Client::get_ssl_client_cert_pw_prompt_provider( $self->can('_ssl_client_cert_pw_prompt'), 2 ),
        SVN::Client::get_username_prompt_provider( $self->can('_username_prompt'), 2),
    ]);

    $self->_auth_baton($baton);
    $self->_auth_ref($ref);
}

# Implement auth callbacks
# simple_prompt ssl_server_trust ssl_client_cert ssl_client_cert_pw username


=back

=head2 METHODS

=over

=item find_changeset_from_remote($remote_identifier)

=item traverse_new_changesets()

=item mirror_changesets

=item get_commit_editor

=item url


=cut


1;

