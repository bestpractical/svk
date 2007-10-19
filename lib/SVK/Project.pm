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
    my ( $self, $match ) = @_;

    my $fs              = $self->depot->repos->fs;
    my $root            = $fs->revision_root( $fs->youngest_rev );
    my $branch_location = $self->branch_location;

    return [ apply {s{^\Q$branch_location\E/}{}}
        @{ $self->_find_branches( $root, $self->branch_location ) } ];
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

sub create_from_path {
    my ($self, $depot, $path) = @_;
    my $root;
    my $rev = undef;

    my $path_obj = SVK::Path->real_new(
        {   depot    => $depot,
            path     => $path
        }
    );
    $path_obj->refresh_revision;

    my $depotpath = $path_obj->{path};
    my ($project_name) = $depotpath =~ m{^/.*/([\w\-_]+)(?:/(?:trunk|branches|tags))?};

    return 0 unless $project_name; # so? 0 means? need to deal with it.

    my $mirror_path = "/mirror";
    my ($trunk_path, $branch_path, $tag_path) = 
	map { $mirror_path."/".$project_name."/".$_ } ('trunk', 'branches', 'tags');
    # check trunk, branch, tag, these should be metadata-ed 
    for my $_path ($trunk_path, $branch_path, $tag_path) {
	# we check if the structure of mirror is correct
	# need more handle here
	die $! unless $SVN::Node::dir == $path_obj->root->check_path($_path);
    }
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

1;
