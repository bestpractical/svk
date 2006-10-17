package SVK::Mirror::Backend::SVNRa;
use strict;
use warnings;

# We'll extract SVK::Mirror::Backend later.
# use base 'SVK::Mirror::Backend';
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw());

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

=back

=head2 METHODS

=over

=cut


1;

