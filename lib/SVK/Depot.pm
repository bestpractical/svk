package SVK::Depot;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(repos repospath depotname));

sub mirror {
    my $self = shift;
    return SVK::MirrorCatalog->new
	( { repos => $self->repos,
	    revprop => ['svk:signature'] });
}

1;
