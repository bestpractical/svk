package SVK::Path::CommandTargetRole;
use Moose::Role;

with('MooseX::Clone');

#requires $_ for qw(same_repos same_source is_mirrored normalize path universal contains_mirror  related_to copied_from search_revision merged_from revision path_target as_url);

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
