package SVK::Mirror::Backend::SVNRa;
use strict;
use warnings;

use SVN::Core;
use SVN::Ra;
use SVN::Client ();

use constant OK => $SVN::_Core::SVN_NO_ERROR;

# We'll extract SVK::Mirror::Backend later.
# use base 'SVK::Mirror::Backend';
use base 'Class::Accessor::Fast';

# for this: things without _'s will probably move to base
# SVK::Mirror::Backend
__PACKAGE__->mk_accessors(qw(mirror url _config _auth_baton _auth_ref _auth_baton));

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

    my $self = $class->SUPER::new({ mirror => $mirror });

    print "DEBUG: going into _new_ra\n";
    my $ra = $self->_new_ra;
    print "DEBUG: done with _new_ra\n";
    
    # init the svm:source and svm:uuid thing on $mirror->path
    # note that the ->source is splitted with '!' and put into source_root and source_path (or something)

    return $self;
}

sub _new_ra {
    my ($self) = @_;

    $self->_initialize_svn;
    print "DEBUG: making ra\n";
    return SVN::Ra->new( url => $self->url,
                         auth => $self->_auth_baton,
                         config => $self->_config );
}

sub _initialize_svn {
    my ($self) = @_;

    $self->_config( SVN::Core::config_get_config(undef, $self->mirror->pool) )
      unless $self->_config;
    $self->_initialize_auth
      unless $self->_auth_baton;
}

sub _initialize_auth {
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
sub _simple_prompt {
    my ($cred, $realm, $default_username, $may_save, $pool) = @_;

    if (defined $default_username and length $default_username) {
        print "Authentication realm: $realm\n" if defined $realm and length $realm;
        $cred->username($default_username);
    }
    else {
        _username_prompt($cred, $realm, $may_save, $pool);
    }

    $cred->password(_read_password("Password for '" . $cred->username . "': "));
    $cred->may_save($may_save);

    return OK;
}

sub _ssl_server_trust_prompt {
    my ($cred, $realm, $failures, $cert_info, $may_save, $pool) = @_;

    print "Error validating server certificate for '$realm':\n";

    print " - The certificate is not issued by a trusted authority. Use the\n",
          "   fingerprint to validate the certificate manually!\n"
      if ($failures & $SVN::Auth::SSL::UNKNOWNCA);

    print " - The certificate hostname does not match.\n"
      if ($failures & $SVN::Auth::SSL::CNMISMATCH);

    print " - The certificate is not yet valid.\n"
      if ($failures & $SVN::Auth::SSL::NOTYETVALID);

    print " - The certificate has expired.\n"
      if ($failures & $SVN::Auth::SSL::EXPIRED);

    print " - The certificate has an unknown error.\n"
      if ($failures & $SVN::Auth::SSL::OTHER);

    printf(
        "Certificate information:\n".
        " - Hostname: %s\n".
        " - Valid: from %s until %s\n".
        " - Issuer: %s\n".
        " - Fingerprint: %s\n",
        map $cert_info->$_, qw(hostname valid_from valid_until issuer_dname fingerprint)
    );

    print(
        $may_save
            ? "(R)eject, accept (t)emporarily or accept (p)ermanently? "
            : "(R)eject or accept (t)emporarily? "
    );

    my $choice = lc(substr(<STDIN> || 'R', 0, 1));

    if ($choice eq 't') {
        $cred->may_save(0);
        $cred->accepted_failures($failures);
    }
    elsif ($may_save and $choice eq 'p') {
        $cred->may_save(1);
        $cred->accepted_failures($failures);
    }

    return OK;
}

sub _ssl_client_cert_prompt {
    my ($cred, $realm, $may_save, $pool) = @_;

    print "Client certificate filename: ";
    chomp(my $filename = <STDIN>);
    $cred->cert_file($filename);

    return OK;
}

sub _ssl_client_cert_pw_prompt {
    my ($cred, $realm, $may_save, $pool) = @_;

    $cred->password(_read_password("Passphrase for '%s': "));

    return OK;
}

sub _username_prompt {
    my ($cred, $realm, $may_save, $pool) = @_;

    print "Authentication realm: $realm\n" if defined $realm and length $realm;
    print "Username: ";
    chomp(my $username = <STDIN>);
    $username = '' unless defined $username;

    $cred->username($username);

    return OK;
}

sub _read_password {
    my ($prompt) = @_;

    print $prompt;

    require Term::ReadKey;
    Term::ReadKey::ReadMode('noecho');

    my $password = '';
    while (defined(my $key = Term::ReadKey::ReadKey(0))) {
        last if $key =~ /[\012\015]/;
        $password .= $key;
    }

    Term::ReadKey::ReadMode('restore');
    print "\n";

    return $password;
}




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

