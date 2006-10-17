package SVK::Mirror::Backend::SVNRa;
use strict;
use warnings;

# We'll extract SVK::Mirror::Backend later.
# use base 'SVK::Mirror::Backend';
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(mirror ));

=head1 NAME

SVK::Mirror::Backend::SVNRa - 

=head1 SYNOPSIS


=head1 DESCRIPTION

=over

=item new

=cut

sub new {
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

