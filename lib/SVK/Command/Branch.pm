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
use SVK::Logger;

our $fromProp;
use constant narg => undef;

my @SUBCOMMANDS = qw(merge move push remove|rm|del|delete checkout|co create diff info setup online offline);

sub options {
    ('l|list'           => 'list',
     'C|check-only'     => 'check_only',
     'P|patch=s'        => 'patch',
     'all'              => 'all',
     'from=s'           => 'from',
     'local'            => 'local',
     'project=s'        => 'project',
     'switch-to'        => 'switch',
     'tag'              => "tag",
     'verbose'          => 'verbose', # TODO
     map { my $cmd = $_; s/\|.*$//; ($cmd => $_) } @SUBCOMMANDS
    );
}

sub lock {} # override commit's locking

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    my $target;
    my $project_name = $self->{project};
    eval {
	$target = $self->arg_co_maybe(pop @arg);
    };
    if ($@) { # then it means we need to find the project
	my @depots =  sort keys %{ $self->{xd}{depotmap} };
	my $proj;
	foreach my $depot (@depots) {
	    $depot =~ s{/}{}g;
	    $target = eval { $self->arg_depotpath("/$depot/") };
	    next if ($@);
	    $proj = SVK::Project->create_from_prop($target, $project_name);
	    last if ($proj) ;
	}
    }
#    if ($arg[0] eq 'push') {
#	shift @arg;
#	local *$self->run = sub SVK::Command::Smerge::run;
#	return SVK::Command::Branch::push::parse_arg($self,@arg);
#    }
    return ($target, @arg);
}

sub run {
    my ( $self, $target, @options ) = @_;
#    return SVK::Command::Branch::push::run($self,@options) if $target eq 'push';

    my $proj = $self->load_project($target);

    if ($proj) {
        $proj->info($target);
    } else {
        $target->root->check_path($target->path)
            or die loc("Path %1 does not exist.\n", $target->depotpath);
    }

    return;
}

sub load_project {
    my ($self, $target) = @_;
    $fromProp = 0;

    Carp::cluck unless $target->isa('SVK::Path') or $target->isa('SVK::Path::Checkout');
    $target = $target->source if $target->isa('SVK::Path::Checkout');
    my $proj = SVK::Project->create_from_prop($target, $self->{project});
    $fromProp = 1 if $proj;
    $proj ||= SVK::Project->create_from_path(
	    $target->depot, $target->path );
    return $proj if $proj;

    return if $self->{setup};
    if ($SVN::Node::dir == $target->root->check_path($target->_to_pclass($target->path)->subdir('trunk'))) {
	my $possible_pname = $target->_to_pclass($target->path)->dir_list(-1);
	$logger->info(
	    loc("I found a \"trunk\" directory for project '%1', but I can't find a \"branches\" directory.",
		$possible_pname)
	);
	$logger->info(
	    loc('You should either run "svk mkdir %1/branches" to set up the standard',
		$target->depotpath)
	);
	$logger->info(
	    loc('project layout or run "svk br --setup %1" to specify an alternate layout.',
		$target->depotpath)
	);
    } else {
	$logger->info(
	    loc("Project not found. use 'svk branch --setup %1' to initial.\n", $target->depotpath)
	);
    }
    return ;
}

sub expand_branch {
    my ($self, $proj, $arg) = @_;
    return $arg unless $arg =~ m/\*/;
    my $match = SVK::XD::compile_apr_fnmatch($arg);
    return grep { m/$match/ } @{ $proj->branches };
}

package SVK::Command::Branch::list;
use base qw(SVK::Command::Branch);
use SVK::I18N;
use SVK::Logger;

sub run {
    my ($self, $target) = @_;

    my $proj = $self->load_project($target);

    if (!$proj) {
	$logger->info( loc("No project found.\n"));
	return;
    }

    if ($self->{all}) {
	my $fmt = "%s%s\n"; # here to change layout

	my $branches = $proj->branches (0); # branches
	$logger->info (sprintf $fmt, $_, '') for @{$branches};
	
	$branches = $proj->tags ();         # tags
	$logger->info (sprintf $fmt, $_, ' (tags)') for @{$branches};

	$branches = $proj->branches (1);    # local branches
	$logger->info (sprintf $fmt, $_, ' (in local)') for @{$branches};

    } else {
	my $branches = $proj->branches ($self->{local});

	my $fmt = "%s\n"; # here to change layout
	$logger->info (sprintf $fmt, $_) for @{$branches};
    }
    return;
}

package SVK::Command::Branch::create;
use base qw( SVK::Command::Copy SVK::Command::Switch SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri );
use SVK::Logger;

sub lock { $_[0]->lock_target ($_[1]); };

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg > 1;

    my $dst = shift (@arg);
    die loc ("Copy destination can't be URI.\n")
	if is_uri ($dst);

    @arg = ('') if $#arg < 0;

    die loc ("Copy source can't be URI.\n")
	if is_uri ($arg[0]);

    my $target;
    eval {
	$target = $self->arg_co_maybe($arg[0]);
    };
    if ($@) { 
	$logger->info( "I can't figure out what project you'd like to create a branch in. Please");
	$logger->info("either run '$0 branch --create' from within an existing chekout or specify");
	$logger->info("a project root using the --project flag");
	die $@;
    }
    return ($target, $dst);
}


sub run {
    my ($self, $target, $branch_name) = @_;

    my $proj = $self->load_project($target);

    if (!$proj) {
	$logger->info( loc("No project found.\n"));
	return;
    }

    delete $self->{from} if $self->{from} and $self->{from} eq 'trunk';
    my $src_path = $proj->branch_path($self->{from} ? $self->{from} : 'trunk');
    my $newbranch_path = $self->dst_path($proj, $branch_name);

    my $src = $self->arg_uri_maybe($src_path);
    die loc("Invalid --from argument") if
	$SVN::Node::none == $src->root->check_path($src->path);
    my $dst = $self->arg_uri_maybe($newbranch_path);
    $SVN::Node::none == $dst->root->check_path($dst->path)
	or die loc("Project branch already exists: %1 %2\n",
	    $branch_name, $self->{local} ? '(in local)' : '');

    $self->{parent} = 1;
    $self->{message} ||= "- Create branch $branch_name";
    my $ret = $self->SUPER::run($src, $dst);

    if (!$ret) {
	$logger->info( loc("Project %1 created: %2%3%4\n",
        $self->{tag} ? "tag" : "branch",
	    $branch_name,
	    $self->{local} ? ' (in local)' : '',
	    $self->{from} ? " (from $self->{from})" : '',
	  )
	);
	# call SVK::Command::Switch here if --switch-to
	$self->SVK::Command::Switch::run(
	    $self->arg_uri_maybe($newbranch_path),
	    $target
	) if $self->{switch} and !$self->{check_only};
    }
    return;
}

sub dst_path {
    my ( $self, $proj, $branch_name ) = @_;

    if ( $self->{tag} ) {
        $proj->tag_path($branch_name);
    } else {
        $proj->branch_path($branch_name, $self->{local});
    }
}

package SVK::Command::Branch::move;
use base qw( SVK::Command::Move SVK::Command::Smerge SVK::Command::Delete SVK::Command::Branch::create );
use SVK::I18N;
use SVK::Util qw( is_uri );
use Path::Class;

sub lock { $_[0]->lock_coroot ($_[1]); };

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    my $dst = pop(@arg);
    die loc ("Copy destination can't be URI.\n")
	if is_uri ($dst);

    for (@arg) {
	die loc ("Copy source can't be URI.\n")
	    if is_uri ($_);
    }
    push @arg, '' unless @arg;

    return ($self->arg_co_maybe (''), $dst, @arg);
}

sub run {
    my ($self, $target, $dst_path, @src_paths) = @_;

    my $proj = $self->load_project($target);

    my $depot_root = '/'.$proj->depot->depotname;
    my $branch_path = $depot_root.$proj->branch_location;
    my $dst_branch_path = $dst_path;
    $dst_branch_path = $branch_path.'/'.$dst_path.'/'
	unless $dst_path =~ m#^$depot_root/#;
    my $dst = $self->arg_depotpath($dst_branch_path);
    $SVN::Node::none == $dst->root->check_path($dst->path)
	or $SVN::Node::dir == $dst->root->check_path($dst->path)
	or die loc("Project branch already exists: %1 %2\n",
	    $branch_path, $self->{local} ? '(in local)' : '');

    $self->{parent} = 1;
    for my $src_path (@src_paths) {
	my $src_branch_path = $src_path;
	$src_branch_path = $branch_path.'/'.$src_path.'/'
	    unless $src_path =~ m#^$depot_root/#;
	$src_branch_path = $depot_root.$target->source->path
	    unless ($src_path);
	my $src = $self->arg_co_maybe($src_branch_path);

	if ( !$dst->same_source($src) ) {
	    # branch first, then sm -I
	    my ($which_depotpath, $which_rev_we_branch) =
		(($src->copy_ancestors)[0]->[0], ($src->copy_ancestors)[0]->[1]);
	    $self->{rev} = $which_rev_we_branch;
	    $src = $self->arg_uri_maybe($depot_root.'/'.$which_depotpath);
	    $self->{message} = "- Create branch $src_branch_path to $dst_branch_path";
	    local *handle_direct_item = sub {
		my $self = shift;
		$self->SVK::Command::Copy::handle_direct_item(@_);
	    };
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
	    $dst->refresh_revision;
	} else {
	    $self->{message} = "- Move branch $src_branch_path to $dst_branch_path";
	    my $ret = $self->SVK::Command::Move::run($src, $dst);
	}
	$self->{rev} = $dst->revision; # required by Command::Switch
	$self->SVK::Command::Switch::run(
	    $self->arg_uri_maybe($dst_branch_path),
	    $target
	) if $target->_to_pclass($target->path) eq $target->_to_pclass($src_branch_path)
	    and !$self->{check_only};
    }
    return;
}

package SVK::Command::Branch::remove;
use base qw( SVK::Command::Delete SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri is_depotpath);
use SVK::Logger;

sub lock { $_[0]->lock_target ($_[1]); };

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    for (@arg) {
	die loc ("Copy source can't be URI.\n")
	    if is_uri ($_);
    }

    # if specified project path at the end
    my $project_path = pop @arg if $#arg > 0 and is_depotpath($arg[$#arg]);
    $project_path = '' unless $project_path;
    return ($self->arg_co_maybe ($project_path), @arg);
}


sub run {
    my ($self, $target, @dsts) = @_;

    my $proj = $self->load_project($target);

    @dsts = map { $self->expand_branch($proj, $_) } @dsts;

    @dsts = grep { defined($_) } map { 
	my $target_path = $proj->branch_path($_, $self->{local});

	my $target = $self->arg_uri_maybe($target_path);
	$target = $target->root->check_path($target->path) ? $target : undef;
	$target ? 
	    $self->{message} .= "- Delete branch ".$target->path."\n" :
	    $logger->info ( loc("No such branch exists: %1 %2",
		$_, $self->{local} ? '(in local)' : '')
	    );

	$target;
    } @dsts;

    $self->SUPER::run(@dsts) if @dsts;

    return;
}

package SVK::Command::Branch::merge;
use base qw( SVK::Command::Smerge SVK::Command::Branch);
use SVK::I18N;
use SVK::Util qw( is_uri abs_path );
use Path::Class;

use constant narg => 1;

sub lock { $_[0]->lock_target ($_[1]) if $_[1]; };

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

    my $proj = $self->load_project($target);

    @srcs = map { $self->expand_branch($proj, $_) } @srcs;

    my $dst_depotpath = $dst;
    $dst_depotpath = '/'.$proj->depot->depotname.'/'.$proj->trunk
	if $dst eq 'trunk';
    $dst_depotpath = $proj->depotpath_in_branch_or_tag($dst_depotpath) || $dst_depotpath;
    $dst = $self->arg_co_maybe($dst_depotpath);
    $dst->root->check_path($dst->path)
	or die loc("Path or branche %1 does not included in current Project\n", $dst->depotpath);
    $dst_depotpath = $dst->depotpath;

    $dst = $self->arg_depotpath($dst_depotpath);

    # see also check_only in incmrental smerge.  this should be a
    # better api in svk::path
    if ($self->{check_only}) {
        require SVK::Path::Txn;
        $dst = $dst->clone;
        bless $dst, 'SVK::Path::Txn'; # XXX: need a saner api for this
    }

    for my $src (@srcs) {
	my $src_branch_path = $proj->depotpath_in_branch_or_tag($src);
	$src_branch_path =  '/'.dir($proj->depot->depotname,$proj->trunk)
	    if $src eq 'trunk';
	$src = $self->arg_depotpath($src_branch_path);

	$self->{message} = "- Merge $src_branch_path to ".$dst->depotpath;
	my $ret = $self->SUPER::run($src, $dst);
	$dst->refresh_revision;
    }
    return;
}

package SVK::Command::Branch::push;
use base qw( SVK::Command::Push SVK::Command::Branch);
use SVK::I18N;
use SVK::Logger;

sub parse_arg {
    my ($self, @arg) = @_;

    my ($target, $proj, $dst);
    my $project_name = $self->{project};
    eval { # always try to eval current wc
	$target = $self->arg_co_maybe('');
    };
    if ($@) { # then it means we must have a project
	my @depots =  sort keys %{ $self->{xd}{depotmap} };
	my $proj;
	foreach my $depot (@depots) {
	    $depot =~ s{/}{}g;
	    $target = eval { $self->arg_depotpath("/$depot/") };
	    next if ($@);
	    $proj = SVK::Project->create_from_prop($target, $project_name);
	    last if ($proj) ;
	}
    } else {
	$proj = $self->load_project($target, $self->{project});
    }
    if (!$proj) {
	$logger->info( loc("Project not found."));
	return ;
    }
    $target = $target->source if $target->isa('SVK::Path::Checkout');
    if (@arg) {
	my $src_bname = pop (@arg);
	my $src = $self->arg_depotpath($proj->branch_path($src_bname));
	if ($SVN::Node::dir != $target->root->check_path($src->path)) {
	    $src = $self->arg_depotpath($proj->tag_path($src_bname));
	    die loc("No such branch/tag exists: %1\n", $src->path)
		if ($SVN::Node::dir != $target->root->check_path($src->path)) ;
	}
	$self->{from} = 0;
	$self->{from_path} = $src->depotpath;
    }

    $self->SUPER::parse_arg (@arg);
}

package SVK::Command::Branch::checkout;
use base qw( SVK::Command::Checkout SVK::Command::Branch );
use SVK::I18N;
use SVK::Logger;
use SVK::Util qw( is_depotpath );

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0 or $#arg > 2;

    my $branch_name = shift(@arg);
    my ($project_path, $checkout_path) = ('','');
    if (@arg and is_depotpath($arg[$#arg])) {
	$project_path = pop(@arg);
    }
    $checkout_path = pop(@arg);
    $checkout_path = $branch_name unless $checkout_path;
    
    if (@arg) { # this must be a project path, or error it
	$project_path = pop(@arg);
	if (!is_depotpath($project_path)) {
	    $logger->info(
		loc("No avaliable Projects found in %1.\n", $project_path )
	    );
	    return;
	}
    }

    my $target = $self->arg_co_maybe ($project_path);
    my $proj = $self->load_project($target);

    if (!$proj) {
        $logger->info(
            loc("Project not found. use 'svk branch --setup mirror_path' to initial one.\n")
        );
	return ;
    }

    my $newtarget_path = $proj->branch_path($branch_name, $self->{local});
    unshift @arg, $newtarget_path, $checkout_path;
    return $self->SUPER::parse_arg(@arg);
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

    my $proj = $self->load_project($target);

    my $newtarget_path = $proj->branch_path($new_path, $self->{local});

    $self->SUPER::run(
	$self->arg_uri_maybe($newtarget_path),
	$target
    );
    return;
}

package SVK::Command::Branch::diff;
use base qw( SVK::Command::Diff SVK::Command::Branch );
use SVK::I18N;
use SVK::Logger;

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg > 1;

    my ($target, $proj, $dst);
    my $project_name = $self->{project};
    eval { # always try to eval current wc
	$target = $self->arg_co_maybe('');
    };
    if ($@) { # then it means we must have a project
	my @depots =  sort keys %{ $self->{xd}{depotmap} };
	my $proj;
	foreach my $depot (@depots) {
	    $depot =~ s{/}{}g;
	    $target = eval { $self->arg_depotpath("/$depot/") };
	    next if ($@);
	    $proj = SVK::Project->create_from_prop($target, $project_name);
	    last if ($proj) ;
	}
    } else {
	$proj = $self->load_project($target, $self->{project});
    }
    if (!$proj) {
	$logger->info( loc("Project not found."));
	return ;
    }
    if (@arg) {
	my $dst_branch_path = $proj->branch_path(pop(@arg));
	$dst = $self->arg_co_maybe($dst_branch_path);
	if (@arg) {
	    my $src_branch_path = $proj->branch_path(pop(@arg));
	    $target = $self->arg_co_maybe($src_branch_path);
	}
    }

    return ($target, $dst);
}

package SVK::Command::Branch::info;
use base qw( SVK::Command::Info SVK::Command::Branch );
use SVK::I18N;
use SVK::Logger;

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    my ($target, $proj, $dst);
    my $project_name = $self->{project};
    eval { # always try to eval current wc
	$target = $self->arg_co_maybe($arg[0]);
    };
    if ($@) { # then it means we must have a project
	my @depots =  sort keys %{ $self->{xd}{depotmap} };
	my $proj;
	foreach my $depot (@depots) {
	    $depot =~ s{/}{}g;
	    $target = eval { $self->arg_depotpath("/$depot/") };
	    next if ($@);
	    $proj = SVK::Project->create_from_prop($target, $project_name);
	    last if ($proj) ;
	}
    } else {
	$proj = $self->load_project($target, $self->{project});
    }
    if (!$proj) {
	$logger->info( loc("Project not found."));
	return ;
    }

    undef $self->{recursive};
    return map {$self->arg_co_maybe ($proj->branch_path($_))} @arg;
}

package SVK::Command::Branch::setup;
use base qw( SVK::Command::Propset SVK::Command::Branch );
use SVK::I18N;
use SVK::Util qw( is_uri get_prompt );
use SVK::Logger;

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg != 0;

    my $dst = shift(@arg);
    die loc ("Copy destination can't be URI.\n")
        if is_uri ($dst);

    return ($self->arg_co_maybe ($dst));
}


sub run {
    my ($self, $target) = @_;

    my $proj = $self->load_project($target);
    my $local_root = $self->arg_depotpath('/'.$target->depot->depotname.'/');
    my ($trunk_path, $branch_path, $tag_path, $project_name, $preceding_path);

    for my $path ($target->depot->mirror->entries) {
	next unless $target->path =~ m{^$path};
	($trunk_path) = $target->path =~ m{^$path(/?.*)$};
	$project_name = $target->_to_pclass($target->path)->dir_list(-1);
	$project_name = $target->_to_pclass($target->path)->dir_list(-2)
	    if $project_name eq 'trunk';
	$preceding_path = $path;
	last if $trunk_path;
    }

    if ($proj && $fromProp) {
	$logger->info( loc("Project already set in properties: %1\n", $target->depotpath));
	my $proplist = $local_root->root->node_proplist('/');
	if (!exists $proplist->{"svk:project:$project_name:path-trunk"}) {
	    my $ans = lc (get_prompt(
		loc("Would you like to pull the project '%1' settings? [Y/n]", $project_name)
	    ) );
	    if ($ans ne 'n') {
		$self->{message} = "- Mirror properties for project $project_name";

		$proplist = $local_root->root->node_proplist($preceding_path);
		for my $p ( map {'svk:project:'.$project_name.':'.$_}
		    ('path-trunk', 'path-branches', 'path-tags')) {
		    $self->do_propset($p,$proplist->{$p}, $local_root);
		}
		$self->do_propset("svk:project:$project_name:root",$preceding_path, $local_root);
	    }
	}
    } else {
	if (!$proj) {
	    $logger->info( loc("New Project depotpath encountered: %1\n", $target->path));
	} else {
	    $logger->info( loc("Project detected in specified path.\n"));
	    $project_name = $proj->name;
	    $trunk_path = '/'.$proj->trunk;
	    $trunk_path =~ s#^/?$preceding_path##;
	    $branch_path = '/'.$proj->branch_location;
	    $branch_path =~ s{^/?$preceding_path}{};
	    $tag_path = '/'.$proj->tag_location;
	    $tag_path =~ s{^/?$preceding_path}{};
	}
	{
	    my $ans = get_prompt(
		loc("Specify a project name (enter to use '%1'): ", $project_name),
		qr/^(?:[A-Za-z][-+_A-Za-z0-9]*|$)/
	    );
	    if (length($ans)) {
		$project_name = $ans;
		last;
	    }
	}
	$trunk_path ||= $target->_to_pclass('/')->subdir('trunk');
	{
	    my $ans = get_prompt(
		loc("It has no trunk, where is the trunk/? (press enter to use %1)\n=>", $trunk_path),
		qr/^(?:\/?[A-Za-z][-+.A-Za-z0-9]*|$)/

	    );
	    if (length($ans)) {
		$trunk_path = $ans;
		last;
	    }
	}
	$branch_path ||= $target->_to_pclass($trunk_path)->parent->subdir('branches');
	{
	    my $ans = get_prompt(
		loc("And where is the branches/? (%1)\n=> ", $branch_path),
		qr/^(?:\/?[A-Za-z][-+.A-Za-z0-9]*|^\/|$)/
	    );
	    if (length($ans)) {
		$branch_path = $ans;
		last;
	    }
	}
	$tag_path ||= $target->_to_pclass($trunk_path)->parent->subdir('tags');
	{
	    my $ans = get_prompt(
		loc("And where is the tags/? (%1) (or 's' to skip)", $tag_path),
		qr/^(?:\/?[A-Za-z][-+.A-Za-z0-9]*|$)/
	    );
	    if (length($ans)) {
		$tag_path = $ans;
		$tag_path = '' if lc($ans) eq 's';
		last;
	    }
	}
	#XXX implement setting properties of project here
	$self->{message} = "- Setup properties for project $project_name";
	# always set to local first
	$self->do_propset("svk:project:$project_name:path-trunk",$trunk_path, $local_root);
	$self->do_propset("svk:project:$project_name:path-branches",$branch_path, $local_root);
	$self->do_propset("svk:project:$project_name:path-tags",$tag_path, $local_root);
	$self->do_propset("svk:project:$project_name:root",$preceding_path, $local_root);
	my $root_depot = $self->arg_depotpath('/'.$target->depot->depotname.$preceding_path);
	if (0) { # how do we ask user to push to remote?
	    $self->do_propset("svk:project:$project_name:path-trunk",$trunk_path, $root_depot);
	    $self->do_propset("svk:project:$project_name:path-branches",$branch_path, $root_depot);
	    $self->do_propset("svk:project:$project_name:path-tags",$tag_path, $root_depot);
	}
	my $proj = SVK::Project->create_from_prop($target);
	# XXX: what if it still failed here? How to rollback the prop commits?
	if (!$proj) {
	    $logger->info( loc("Project setup failed.\n"));
	} else {
	    $logger->info( loc("Project setup success.\n"));
	}
	return;
    }
    return;
}

package SVK::Command::Branch::online;
use base qw( SVK::Command::Branch::move SVK::Command::Smerge SVK::Command::Switch );
use SVK::I18N;
use SVK::Logger;
use SVK::Util qw( is_uri );

sub lock { $_[0]->lock_target ($_[1]); };

sub parse_arg {
    my ($self, $arg) = @_;
    die loc ("Destination can't be URI.\n")
	if $arg and is_uri ($arg);

    my $target = $self->arg_co_maybe('');
    $self->{switch} = 1 if $target->isa('SVK::Path::Checkout');
    # XXX: should we verbose the branch_name here?
#    die loc ("Current branch '%1' already online\n", $self->{branch_name})
    die loc ("Current branch already online\n")
	if (!$target->_to_pclass("/local")->subsumes($target->path));

    my $proj = $self->load_project($target);

    $self->{branch_name} = $arg if $arg;
    $self->{branch_name} = $proj->branch_name($target->path, 1)
	unless $arg;

    # check existence of remote branch
    my $dst = $self->arg_depotpath($proj->branch_path($self->{branch_name}));
    if ($SVN::Node::none != $dst->root->check_path($dst->path)) {
	$self->{go_smerge} = $dst->depotpath if $target->related_to($dst);
    }

    return ($target, $self->{branch_name}, $target->depotpath);
}

sub run {
    my ($self, $target, @args) = @_;

    if ($self->{go_smerge}) {
	my $dst = $self->arg_depotpath($self->{go_smerge});
	
	$self->{message} = "";
	$self->{incremental} = 1;
	$self->SVK::Command::Smerge::run($target->source, $dst);

	$dst->refresh_revision;

	# XXX: we have a little conflict in private hash argname.
	$self->{rev} = undef;
	$self->SVK::Command::Switch::run($dst, $target) if $target->isa('SVK::Path::Checkout');
    } else {
	$self->SUPER::run($target, @args);
    }
}

package SVK::Command::Branch::offline;
use base qw( SVK::Command::Branch::create );
use SVK::I18N;
use SVK::Logger;

# --offline FOO:
#   --create FOO --local  if FOO/local does't exist 

# --offline (at checkout of branch FOO
#   --create FOO --from FOO --local

sub parse_arg {
    my ($self, @arg) = @_;

    push @arg, '' unless @arg;
    return $self->SUPER::parse_arg(@arg);
}

sub run {
    my ($self, $target, $branch_name) = @_;

    die loc ("Current branch already offline\n")
	if ($target->_to_pclass("/local")->subsumes($target->path));

    my $proj = $self->load_project($target);
    if (!$branch_name) { # no branch_name means using current branch(trunk) as src
	$branch_name = $proj->branch_name($target->path);
	$self->{from} = $branch_name;
    }
    $self->{local} = 1;
    $self->{switch} = 1;

    # check existence of local branch
    my $local = $self->arg_depotpath(
	$proj->branch_path($branch_name, $self->{local})
    );
    if ($SVN::Node::none != $local->root->check_path($local->path)  and
	$target->related_to($local)) {

	$self->{message} = "";
	# XXX: Following copy from ::online, maybe need refactoring
	$self->{incremental} = 1;
	$self->SVK::Command::Smerge::run($target->source, $local);

	$local->refresh_revision;

	# XXX: we have a little conflict in private hash argname.
	$self->{rev} = undef;
	$self->SVK::Command::Switch::run($local, $target) if $target->isa('SVK::Path::Checkout');
    } else {
	$self->SUPER::run($target, $branch_name);
    }
}

1;

__DATA__

=head1 NAME

SVK::Command::Branch - Manage a project with its branches

=head1 SYNOPSIS

 branch --create BRANCH [DEPOTPATH]

 branch --list [--all]
 branch --create BRANCH [--tag] [--local] [--switch-to] [DEPOTPATH]
 branch --move BRANCH1 BRANCH2
 branch --merge BRANCH1 BRANCH2 ... TARGET
 branch --checkout BRANCH [PATH] [DEPOTPATH]
 branch --delete BRANCH1 BRANCH2 ...
 branch --setup DEPOTPATH
 branch --push [BRANCH]

=head1 OPTIONS

 -l [--list]            : list branches for this project
 --create               : create a new branch
 --tag                  : create in the tags directory
 --local                : targets in local branch
 --delete               : delete BRANCH(s)
 --checkout             : checkout BRANCH in current directory
 --switch               : switch the current checkout to another branch
                          (can be paired with --create)
 --merge                : automatically merge all changes from BRANCH1, BRANCH2,
                          etc, to TARGET
 --project              : specify the target project name 
 --push                 : move changes to wherever this branch was copied from
 --setup                : setup a project for a specified DEPOTPATH
 -C [--check-only]      : try a create, move or merge operation but make no     
                          changes


=head1 DESCRIPTION

SVK provides tools to more easily manage your project's branching
and merging, so long as you use the standard "trunk/, branches/, tags/"
directory layout for your project or specifically tell SVK where
your branches live.

SVK branch also provides another project loading mechanism by setting
properties on root path. Current usable properties for SVK branch are 

  'svk:project:<projectName>:path-trunk'
  'svk:project:<projectName>:path-branches'
  'svk:project:<projectName>:path-tags'

These properties are useful when you are not using the standard 
"trunk/, branches/, tags/" directory layout. For example, a mirrored
depotpath '//mirror/projA' may have trunk in "/trunk/projA/" directory, 
branches in "/branches/projA", and have a standard "/tags" directory.
Then by setting the following properties on root path of
remote repository, it can use SVK branch to help manage the project:

  'svk:project:projA:path-trunk => /trunk/projA'
  'svk:project:projA:path-branches => /branches/projA' 
  'svk:project:projA:path-tags => /tags'

Be sure to have all "path-trunk", "path-branches" and "path-tags"
set at the same time.
