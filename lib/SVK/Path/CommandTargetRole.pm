package SVK::Path::CommandTargetRole;
use Moose::Role;

with('MooseX::Clone');

has inspector => (
	isa => "SVK::Inspector",
	is  => "rw",
	clearer => 'clear_inspector',
	traits  => [qw(NoClone)],
	lazy_build => 1,
);

requires '_build_inspector';

has pool => (
	isa  => "SVN::Pool",
	is   => "rw",
	lazy => 1,
	default => sub { SVN::Pool->new },
	traits  => [qw(NoClone)],
);

sub _build_inspector {
    my $self = shift;
    return SVK::Inspector::Root->new
	({ root => $self->repos->fs->revision_root($self->revision, $self->pool),
	   _pool => $self->pool,
	   anchor => $self->path_anchor });
}

1;
