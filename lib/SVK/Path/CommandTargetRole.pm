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

1;
