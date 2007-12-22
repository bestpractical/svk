# BEGIN BPS TAGGED BLOCK {{{
# COPYRIGHT:
# 
# This software is Copyright (c) 2007 Best Practical Solutions, LLC
#                                          <clkao@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of either:
# 
#   a) Version 2 of the GNU General Public License.  You should have
#      received a copy of the GNU General Public License along with this
#      program.  If not, write to the Free Software Foundation, Inc., 51
#      Franklin Street, Fifth Floor, Boston, MA 02110-1301 or visit
#      their web page on the internet at
#      http://www.gnu.org/copyleft/gpl.html.
# 
#   b) Version 1 of Perl's "Artistic License".  You should have received
#      a copy of the Artistic License with this package, in the file
#      named "ARTISTIC".  The license is also available at
#      http://opensource.org/licenses/artistic-license.php.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of the
# GNU General Public License and is only of importance to you if you
# choose to contribute your changes and enhancements to the community
# by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with SVK,
# to Best Practical Solutions, LLC, you confirm that you are the
# copyright holder for those contributions and you grant Best Practical
# Solutions, LLC a nonexclusive, worldwide, irrevocable, royalty-free,
# perpetual, license to use, copy, create derivative works based on
# those contributions, and sublicense and distribute those contributions
# and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
package SVK::Project;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(
    qw(name trunk branch_location tag_location local_root depot));

=head1 NAME

SVK::Project - SVK project class

=head1 SYNOPSIS

 See below

=head1 DESCRIPTION

The class represents a project within svk.

=cut

use List::MoreUtils 'apply';

sub branches {
    my ( $self, $local ) = @_;

    my $fs              = $self->depot->repos->fs;
    my $root            = $fs->revision_root( $fs->youngest_rev );
    my $branch_location = $local ? $self->local_root : $self->branch_location;

    return [ apply {s{^\Q$branch_location\E/}{}}
        @{ $self->_find_branches( $root, $branch_location ) } ];
}

sub tags {
    my $self = shift;

    my $fs              = $self->depot->repos->fs;
    my $root            = $fs->revision_root( $fs->youngest_rev );
    my $tag_location    = $self->tag_location;

    return [ apply {s{^\Q$tag_location\E/}{}}
        @{ $self->_find_branches( $root, $tag_location ) } ];
}

sub _find_branches {
    my ( $self, $root, $path ) = @_;
    my $pool    = SVN::Pool->new_default;
    my $entries = $root->dir_entries($path);

    my $trunk = SVK::Path->real_new(
        {   depot    => $self->depot,
            revision => $root->revision_root_revision,
            path     => $self->trunk
        }
    );

    my @branches;

    for my $entry ( sort keys %$entries ) {
        next unless $entries->{$entry}->kind == $SVN::Node::dir;
        my $b = $trunk->mclone( path => $path . '/' . $entry );

        push @branches, $b->related_to($trunk)
            ? $b->path
            : @{ $self->_find_branches( $root, $path . '/' . $entry ) };
    }
    return \@branches;
}

sub create_from_prop {
    my ($self, $pathobj) = @_;

    my $fs              = $pathobj->depot->repos->fs;
    my $root            = $fs->revision_root( $fs->youngest_rev );
    my $allprops        = $root->node_proplist('/');
    my ($depotroot)     = '/';
    my %projnames = 
        map  { $_ => 1 }
	grep { $_ =~ s/^svk:project:([^:]+):.*$/$1/ }
	grep { $allprops->{$_} =~ /$depotroot/ } sort keys %{$allprops};
    
    for my $project_name (keys %projnames)  {
	my %props = 
	    map { $_ => '/mirror'.$allprops->{'svk:project:'.$project_name.':'.$_} }
		('path-trunk', 'path-branches', 'path-tags');
    
	# only the current path matches one of the branches/trunk/tags, the project
	# is returned
	for my $key (keys %props) {
	    return SVK::Project->new(
		{   
		    name            => $project_name,
		    depot           => $pathobj->depot,
		    trunk           => $props{'path-trunk'},
		    branch_location => $props{'path-branches'},
		    tag_location    => $props{'path-tags'},
		    local_root      => "/local/${project_name}",
		}) if $pathobj->path =~ m/^$props{$key}/;
	}
    }
    return undef;
}

sub create_from_path {
    my ($self, $depot, $path) = @_;
    my $rev = undef;

    my $path_obj = SVK::Path->real_new(
        {   depot    => $depot,
            path     => $path
        }
    );
    $path_obj->refresh_revision;

    my ($project_name, $trunk_path, $branch_path, $tag_path) = 
	$self->_find_project_path($path_obj);

    return undef unless $project_name;
    return SVK::Project->new(
	{   
	    name            => $project_name,
	    depot           => $path_obj->depot,
	    trunk           => $trunk_path,
	    branch_location => $branch_path,
	    tag_location    => $tag_path,
	    local_root      => "/local/${project_name}",
	});
}

# this is heuristics guessing of project and should be replaced
# eventually when we can define project meta data.
sub _find_project_path {
    my ($self, $path_obj) = @_;

    my ($mirror_path,$project_name);
    my ($trunk_path, $branch_path, $tag_path);
    my $depotname = $path_obj->depot->depotname;
    my ($path) = $path_obj->depotpath =~ m{^/$depotname/(.*?)(?:/(?:trunk|branches/.*?|tags/.*?))?/?$};

    if ($path =~ m{^local/([^/]+)/?}) { # guess if in local branch
	# should only be 1 entry
	($path) = grep {/\/$1$/} $path_obj->depot->mirror->entries;
	$path =~ s#^/##;
    }

    while (!$project_name) {
	($mirror_path,$project_name) = # always assume the last entry the projectname
	    $path =~ m{^(.*)/([\w\-_]+)$}; 
	return undef unless $project_name; # can' find any project_name

	($trunk_path, $branch_path, $tag_path) = 
	    map { $mirror_path."/".$project_name."/".$_ } ('trunk', 'branches', 'tags');
	# check trunk, branch, tag, these should be metadata-ed 
	# we check if the structure of mirror is correct, otherwise go again
	for my $_path ($trunk_path, $branch_path, $tag_path) {
            unless ($path_obj->root->check_path($_path) == $SVN::Node::dir) {
                if ($tag_path eq $_path) { # tags directory is optional
                    undef $tag_path;
                }
                else {
                    undef $project_name;
                }
            }
	}
	# if not the last entry, then the mirror_path should contains
	# trunk/branches/tags, otherwise no need to test
	($path) = $mirror_path =~ m{^(.+(?=/(?:trunk|branches|tags)))}
	    unless $project_name;
	return undef unless $path;
    }
    return ($project_name, $trunk_path, $branch_path, $tag_path);
}

1;
