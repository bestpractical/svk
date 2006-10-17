package SVK::Mirror;
use strict;
use warnings;

use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(repos path _backend));

=head1 NAME

SVK::Mirror - 

=head1 SYNOPSIS

    # setup a new mirror
    my $mirror = SVK::Mirror->new( { backend => 'svnra',  url => 'http://server/',
                                     backend_options => {}, repos => $repos, path => '/mirror' } );
    # load existing mirror
    my $existing = SVK::Mirror->load( { path => $path, repos => $repos } );

    $mirror->mirror_changesets();

    $mirror->traverse_changesets( sub { $revs_to_mirror++ } );

=head1 DESCRIPTION

=over

=item new

=cut

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args);

    $self->_backend( $self->_create_backend($args->{backend}, $args->{backend_options}) );

    SVK::MirrorCatalog->add_mirror($self);

    return $self;
}

=item load

=cut

sub load {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args);

}

=back

=head2 METHODS

=over

=item find_changeset($localrev)

=item find_changeset_from_remote($remote_identifier)

=item traverse_new_changesets()

=item mirror_changesets

=item detach

=item get_commit_editor

=item relocate($newurl)

=item with_lock($code)

=item move($newpath)

NOT IMPLEMENTED

=item url

=cut

sub url { $_[0]->_backend->url }

=back

=cut



package SVK::Mirror::ChangeSet;
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(mirror synced));

=over

=item sync

This may only be called when you hold the mirror sync lock.

=cut

sub sync {

}

=back

=cut

1;

