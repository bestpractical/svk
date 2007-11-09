# BEGIN BPS TAGGED BLOCK {{{
# COPYRIGHT:
# 
# This software is Copyright (c) 2003-2006 Best Practical Solutions, LLC
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
package SVK::Command::Branch;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;
use SVK::Util qw( is_uri get_prompt );
use SVK::Project;

use constant narg => undef;

sub options {
    ('l|list'  => 'list',
     'C|check-only'     => 'check_only',
     'create'=> 'create',
     'local'=> 'local',
     'merge'=> 'merge',
     'move' => 'move',
     'remove'=> 'remove',
     'switch-to'=> 'switch',
    );
}

sub lock {} # override commit's locking

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_co_maybe ($_)} @arg;
}

sub run {
    my ( $self, $target, @options ) = @_;

    my $source = $target->source;
    my $proj = SVK::Project->create_from_path(
	$source->depot,
	$source->path
    );

    print loc("Project mapped.  Project name: %1.\n", $proj->name);

    return;
}

package SVK::Command::Branch::list;
use base qw(SVK::Command::Branch);
use SVK::I18N;

sub run {
    my ($self, $target) = @_;

    $target = $target->source if $target->isa('SVK::Path::Checkout');
    my $proj = SVK::Project->create_from_path(
	$target->depot,
	$target->path
    );

    if (!$proj) {
	print loc("No project branch founded.\n");
	return;
    }

    my $branches = $proj->branches;

    my $fmt = "%s\n"; # here to change layout
    printf $fmt, $_ for @{$branches};
    return;
}

package SVK::Command::Branch::create;
use base qw( SVK::Command::Copy SVK::Command::Switch SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri );

sub lock { $_[0]->lock_target ($_[1]); };

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    my $dst = shift(@arg);
    die loc ("Copy destination can't be URI.\n")
	if is_uri ($dst);

    die loc ("More than one URI found.\n")
	if (grep {is_uri($_)} @arg) > 1;

    return ($self->arg_co_maybe (''), $dst);
}


sub run {
    my ($self, $target, $branch_path) = @_;

    my $source = $target->source;
    my $proj = SVK::Project->create_from_path(
	$source->depot,
	$source->path
    );

    my $trunk_path = '/'.$proj->depot->depotname.'/'.$proj->trunk;
    my $newbranch_path = '/'.$proj->depot->depotname.'/'.
	( $self->{local} ? $proj->local_root : $proj->branch_location ).
	'/'.$branch_path.'/';

    my $src = $self->arg_uri_maybe($trunk_path);
    my $dst = $self->arg_uri_maybe($newbranch_path);
    $SVN::Node::none == $dst->root->check_path($dst->path)
	or die loc("Project branch already exists: %1 %2\n",
	    $branch_path, $self->{local} ? '(in local)' : '');

    $self->{parent} = 1;
    $self->{message} ||= "- Create branch $branch_path";
    my $ret = $self->SUPER::run($src, $dst);

    if (!$ret) {
	print loc("Project branch created: %1 %2\n",
	    $branch_path, $self->{local} ? '(in local)' : '');
	# call SVK::Command::Switch here if --switch-to
	$self->SVK::Command::Switch::run(
	    $self->arg_uri_maybe($newbranch_path),
	    $target
	) if $self->{switch};
    }
    return;
}

package SVK::Command::Branch::move;
use base qw( SVK::Command::Copy SVK::Command::Smerge SVK::Command::Move SVK::Command::Delete SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri );

sub lock { $_[0]->lock_coroot ($_[1]); };

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    my $dst = pop(@arg);
    die loc ("Copy destination can't be URI.\n")
	if is_uri ($dst);

    my $src = pop(@arg);
    $src ||= '';
    die loc ("Copy source can't be URI.\n")
	if is_uri ($src);

    return ($self->arg_co_maybe (''), $dst, $src);
}

sub run {
    my ($self, $target, $dst, $src) = @_;

    my $source = $target->source;
    my $proj = SVK::Project->create_from_path(
	$source->depot,
	$source->path
    );

    my $branch_path = '/'.$proj->depot->depotname.'/'.$proj->branch_location;
    my $src_branch_path = $branch_path.'/'.$src.'/';
    my $dst_branch_path = $branch_path.'/'.$dst.'/';
    $src_branch_path = '/'.$proj->depot->depotname.$target->source->path
	unless ($src);

    $src = $self->arg_uri_maybe($src_branch_path);
    $dst = $self->arg_depotpath($dst_branch_path);
    $SVN::Node::none == $dst->root->check_path($dst->path)
	or die loc("Project branch already exists: %1 %2\n",
	    $branch_path, $self->{local} ? '(in local)' : '');

    $self->{parent} = 1;
    if ( !$dst->same_source($src) ) {
	# branch first, then sm -I
	my $which_rev_we_branch = ($src->copy_ancestors)[0]->[1];
	$self->{rev} = $which_rev_we_branch;
	$src = $self->arg_uri_maybe('/'.$proj->depot->depotname.'/'.$proj->trunk);
	$self->{message} = "- Create branch $src_branch_path to $dst_branch_path";
	$self->SVK::Command::Copy::run($src, $dst);
	# now we do sm -I
	$src = $self->arg_uri_maybe($src_branch_path);
	$self->{message} = ''; # incremental does not need message
	# w/o reassign $dst = ..., we will have changes 'XXX - skipped'
	$dst->refresh_revision;
	$dst = $self->arg_depotpath($dst_branch_path);
	$self->{incremental} = 1;
	$self->SVK::Command::Smerge::run($src, $dst);
	$self->{message} = "- Delete branch $src_branch_path, because it move to $dst_branch_path";
	$self->SVK::Command::Delete::run($src, $target);
	return;
    }
    $self->{message} = "- Move branch $src_branch_path to $dst_branch_path";
    my $ret = $self->SVK::Command::Move::run($src, $dst);
    return;
}

package SVK::Command::Branch::remove;
use base qw( SVK::Command::Delete SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri );

sub lock { $_[0]->lock_target ($_[1]); };

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg != 0;

    my $dst = shift(@arg);
    die loc ("Destination can't be URI.\n")
	if is_uri ($dst);

    return ($self->arg_co_maybe (''), $dst);
}


sub run {
    my ($self, $target, $dst_path) = @_;

    my $source = $target->source;
    my $proj = SVK::Project->create_from_path(
	$source->depot,
	$source->path
    );

    my $target_path = '/'.$proj->depot->depotname.'/'.
        ($self->{local} ?
	    $proj->local_root."/$dst_path"
	    :
	    ($dst_path ne 'trunk' ?
		$proj->branch_location . "/$dst_path" : $proj->trunk)
	);

    $target = $self->arg_uri_maybe($target_path);
    $target->root->check_path($target->path)
	or die loc("No such branch exists: %1 %2\n",
	    $dst_path, $self->{local} ? '(in local)' : '');

    $self->{message} = "- Delete branch $target_path";
    $self->SUPER::run($target);
    return;
}

package SVK::Command::Branch::merge;
use base qw( SVK::Command::Smerge SVK::Command::Switch SVK::Command::Branch);
use SVK::I18N;
use SVK::Util qw( is_uri traverse_history );

use constant narg => 1;

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 1;

    my $dst = pop(@arg);
    die loc ("Copy destination can't be URI.\n")
	if is_uri ($dst);

    for (@arg) {
	die loc ("Copy source can't be URI.\n")
	    if is_uri ($_);
    }

    return ($self->arg_co_maybe (''), $dst, @arg);
}

sub run {
    my ($self, $target, $dst, @srcs) = @_;

    my $source = $target->source;
    my $proj = SVK::Project->create_from_path(
	$source->depot,
	$source->path
    );

    my $branch_path = '/'.$proj->depot->depotname.'/'.$proj->branch_location;
    my $dst_branch_path = $branch_path.'/'.$dst;
    $dst_branch_path =  '/'.$proj->depot->depotname.'/'.$proj->trunk
	if $dst eq 'trunk';

    $dst = $self->arg_depotpath($dst_branch_path);

    for my $src (@srcs) {
	my $src_branch_path = $branch_path.'/'.$src;
	$src_branch_path =  '/'.$proj->depot->depotname.'/'.$proj->trunk
	    if $src eq 'trunk';
	$src = $self->arg_depotpath($src_branch_path);

	$self->{message} = "- Merge $src_branch_path to $dst_branch_path";
	my $ret = $self->SUPER::run($src, $dst);
	$dst->refresh_revision;
    }
    return;
}

package SVK::Command::Branch::switch;
use base qw( SVK::Command::Switch SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri );

sub lock { $_[0]->lock_target ($_[1]); };

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg != 0;

    my $dst = shift(@arg);
    die loc ("Copy destination can't be URI.\n")
	if is_uri ($dst);

    die loc ("More than one URI found.\n")
	if (grep {is_uri($_)} @arg) > 1;

    return ($self->arg_co_maybe (''), $dst);
}


sub run {
    my ($self, $target, $new_path) = @_;

    my $source = $target->source;
    my $proj = SVK::Project->create_from_path(
	$source->depot,
	$source->path
    );

    my $newtarget_path = '/'.$proj->depot->depotname.'/'.
        ($self->{local} ?
	    $proj->local_root."/$new_path"
	    :
	    ($new_path ne 'trunk' ?
		$proj->branch_location . "/$new_path/" : $proj->trunk)
	);

    $self->SUPER::run(
	$self->arg_uri_maybe($newtarget_path),
	$target
    );
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Branch - Manage a project with its branches

=head1 SYNOPSIS

 branch --create [BRANCH]

 branch --list [BRANCH...]
 branch --create BRANCH [--switch-to]
 branch --move BRANCH1 BRANCH2

=head1 OPTIONS

 -l [--list]            : list mirrored paths
 -C [--check-only]      : try operation but make no changes
 --create               : create a new branch
 --switch-to            : also switch to another branch
 --merge                : automatically merge all changes between branches

