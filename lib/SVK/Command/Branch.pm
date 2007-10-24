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
use SVK::Util qw( is_uri get_prompt traverse_history );
use SVK::Project;

use constant narg => undef;

sub options {
    ('l|list'  => 'list',
     'move' => 'move',
     'create'=> 'create',
     'switch-to'=> 'switch',
     'local'=> 'local',
     'merge'=> 'merge');
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

    my $source = $target->source;
    my $proj = SVK::Project->create_from_path(
	$source->depot,
	$source->path
    );

    # need to beautify the output
    use Data::Dumper;
    warn Dumper $proj->branches() if $proj; 

    print loc("Project branch listed.\n");
    return;
}

package SVK::Command::Branch::create;
use base qw( SVK::Command::Copy SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri );

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

    my $trunk_path = '//'.$proj->depot->depotname.'/'.$proj->trunk;
    my $newbranch_path = '//'.$proj->depot->depotname.'/'.$proj->branch_location."/".$branch_path."/";
    # XXX if $self->{local};

    my $src = $self->arg_uri_maybe($trunk_path);
    my $dst = $self->arg_depotpath($newbranch_path);

    my $ret = $self->SUPER::run($src, $dst);

    if (!$ret) {
	print loc("Project branch created: %1.\n",$branch_path);
	# call SVK::Command::Switch ?
	# XXX if $self->{switch};
    }
    return;
}

package SVK::Command::Branch::move;
use base qw( SVK::Command::Move SVK::Command::Branch );
use SVK::I18N;

use constant narg => 1;

sub run {
    my ($self, $target) = @_;
    print loc("nothing to move\n");
    return;
}

package SVK::Command::Branch::merge;
use base qw( SVK::Command::Merge SVK::Command::Branch);
use SVK::I18N;

use constant narg => 1;

sub run {
    my ($self, $target) = @_;
    print loc("nothing to merge\n");
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Branch - Initialize a mirrored depotpath

=head1 SYNOPSIS

 branch --create [BRANCH]

 branch --list [DEPOTNAME...]
 branch --create DEPOTPATH [http|svn]://host/path 
 branch --move DEPOTPATH

=head1 OPTIONS

 -l [--list]            : list mirrored paths
 --relocate             : change the upstream URI for the mirrored depotpath
 --recover              : recover the state of a mirror path
 --unlock               : forcibly remove stalled locks on a mirror
 --upgrade              : upgrade mirror state to the latest version

