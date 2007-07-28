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
package SVK::XD;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;

use SVK::I18N;
use SVK::Util qw( get_anchor abs_path abs_path_noexist abs2rel splitdir catdir splitpath $SEP
		  HAS_SYMLINK is_symlink is_executable mimetype mimetype_is_text
		  md5_fh get_prompt traverse_history make_path dirname compile_apr_fnmatch
		  from_native to_native get_encoder get_depot_anchor );
use Data::Hierarchy 0.30;
use autouse 'File::Find' => qw(find);
use autouse 'File::Path' => qw(rmtree);
use autouse 'YAML::Syck'	 => qw(LoadFile DumpFile);
use SVK::MirrorCatalog;
use PerlIO::eol 0.10 qw( NATIVE LF );
use PerlIO::via::dynamic;
use PerlIO::via::symlink;
use Class::Autouse qw( Path::Class SVK::Editor::Delay );
use Fcntl qw(:flock);
use SVK::Depot;
use SVK::Config;

use SVK::Logger;

=head1 NAME

SVK::XD - svk depot and checkout handling.

=head1 SYNOPSIS

  use SVK::XD;
  $xd = SVK::XD->new (depotmap => { '' => '/path/to/repos'});

=head1 TERMINOLOGY

=over

=item depot

A repository referred by a name. The default depot is '' (the empty string).

=item depotpath

A path referred by a depot name and the path inside the depot. For
example, F<//foo/bar> means F</foo/bar> in the default depot '', and
F</test/foo/bar> means F</foo/bar> in the depot B<test>.

=item copath

Checkout path. A path in the file system that has a checked out
version of a certain depotpath.

=back

=head1 CONSTRUCTOR

Options to C<new>:

=over

=item depotmap

A hash reference for depot name and repository path mapping.

=item checkout

A L<Data::Hierarchy> object for checkout paths mapping.

=item giantlock

A filename for global locking.  This file protects all read and write
accesses to the C<statefile>.

When SVK begins to execute any command, it attempt to get a write lock
on this "giant lock" file.  Once it gets the lock, it writes its PID
to the file, reads in its C<statefile>, and begins to execute the
command.  Executing the command consists of a "lock" phase and a "run"
phase.  During the lock phase, a command can do one of three things:
request to keep the giant lock for the entire execution (for commands
which modify large parts of the C<statefile>), request to lock
individual checkout paths, or not request a lock.

In the first case, the command sets the C<hold_giant> field on the
L<SVK::Command> object (this should probably change to a real API),
and the command does not release the giant lock until it is finished;
it can rewrite the C<statefile> at the end of its execution without
waiting on the lock, since it already holds it.

In the second case, the command calls C<lock> on the L<SVK::XD> object
one or more times; this places a "lock" entry inside the
L<Data::Hierarchy> object in the statefile next to each locked path,
unless they are already locked by another process.  Between its lock
phase and its run phase, the C<statefile> is written to disk (with the
new C<lock> entries) and the giant lock is dropped.  After the run
phase, SVK acquires the giant lock again, reads in the C<statefile>,
copies all entries from the paths that it has locked into the version
it just read, clears the lock entries from the hierarchy, writes the
C<statefile> to disk, and drops the giant lock.  Any changes to the
hierarchy other than in the locked paths will be ignored.

In the third case, SVK just drops the giant lock after the lock phase
and never tries to read or write the C<statefile> again.

=item statefile

Filename for serializing C<SVK::XD> object.

=item svkpath

Directory name of C<giantlock> and C<statefile>.

=back

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;

    if ($self->{svkpath}) {
        mkdir($self->{svkpath})
	    or die loc("Cannot create svk-config-directory at '%1': %2\n",
		       $self->{svkpath}, $!)
	    unless -d $self->{svkpath};
        $self->{signature} ||= SVK::XD::Signature->new (root => $self->cache_directory,
                                                        floating => $self->{floating})
    }

    $self->{checkout} ||= Data::Hierarchy->new( sep => $SEP );
    return $self;
}

=head1 METHODS

=head2 Serialization and locking

=over

=item load

Load the serialized C<SVK::XD> data from statefile. Initialize C<$self>
if there's nothing to load. The giant lock is acquired when calling
C<load>.

=cut

sub load {
    my ($self) = @_;
    my $info;

    $self->giant_lock ();

    if (-e $self->{statefile}) {
	local $@;
	$info = eval {LoadFile ($self->{statefile})};
	if ($@) {
	    rename ($self->{statefile}, "$self->{statefile}.backup");
	    $logger->warn(loc ("Can't load statefile, old statefile saved as %1",
		     "$self->{statefile}.backup"));
	}
        elsif ($info) {
            $info->{checkout}{sep} = $SEP;
            $info->{checkout} = $info->{checkout}->to_absolute($self->{floating})
                if $self->{floating};
        }
    }

    $info ||= { depotmap => {'' => catdir($self->{svkpath}, 'local') },
	        checkout => Data::Hierarchy->new( sep => $SEP ) };
    $self->{$_} = $info->{$_} for keys %$info;
    $self->{updated} = 0;
    $self->create_depots('') if exists $self->{depotmap}{''};
}

=item store

=cut

sub create_depots {
    my $self = shift;
    my $depotmap = $self->{depotmap};
    for my $path (@{$depotmap}{sort (@_ ? @_ : keys %$depotmap)}) {
        $path =~ s{[$SEP/]+$}{}go;

	next if -d $path;
	my $ans = get_prompt(
	    loc("Repository %1 does not exist, create? (y/n)", $path),
	    qr/^[yn]/i,
	);
	next if $ans =~ /^n/i;
        $self->_create_depot($path)
    }
    return;
}

sub _create_depot {
    my ($self, $path) = @_;
    make_path(dirname($path));

    SVN::Repos::create($path, undef, undef, undef,
                       {'fs-type' => $ENV{SVNFSTYPE} || 'fsfs',
                        'bdb-txn-nosync' => '1',
                        'bdb-log-autoremove' => '1'});
}


=item store

Serialize C<$self> to the statefile. If giant lock is still ours,
overwrite the file directly. Otherwise load the file again and merge
the paths we locked into the new state file. After C<store> is called,
giant is unlocked.

=cut

sub _store_config {
    my ($self, $hash) = @_;

    $self->{giantlock_handle} or
        die "Internal error: trying to save config without a lock!\n";

    local $SIG{INT} = sub { $logger->warn( loc("Please hold on a moment. SVK is writing out a critical configuration file."))};

    my $file = $self->{statefile};
    my $tmpfile = $file."-$$";
    my $oldfile = "$file~";
    my $ancient_backup = $file.".bak.".$$;

    my $tmphash = { map { $_ => $hash->{$_}} qw/checkout depotmap/ };
    $tmphash->{checkout} = $tmphash->{checkout}->to_relative($self->{floating})
        if $self->{floating};
    DumpFile ($tmpfile, $tmphash);

    if (not -f $tmpfile ) {
        die loc("Couldn't write your new configuration file to %1. Please try again.", $tmpfile);
    }

    if (-f $oldfile ) { 
      rename ( $oldfile => $ancient_backup ) ||
	die loc("Couldn't remove your old backup configuration file %1 while writing the new one: %2.\n", $oldfile, $!);
    }
    if (-f $file ) {
        rename ($file => $oldfile) ||
        	die loc("Couldn't remove your old configuration file %1 while writing the new one: %2.\n", $file, $!);
    }
    rename ($tmpfile => $file) ||
	die loc("Couldn't write your new configuration file %1. A backup has been stored in %2. Please replace %1 with %2 immediately: %3.\n", $file, $tmpfile, $!);

    if (-f $ancient_backup ) {
      unlink ($ancient_backup) ||
	die loc("Couldn't remove your old backup configuration file %1 while writing the new one.", $ancient_backup);

    }
}

sub store {
    my ($self) = @_;
    $self->{updated} = 1;
    return unless $self->{statefile};
    local $@;
    if ($self->{giantlock_handle}) {
        # We never gave up the giant lock, so nobody should have written to
        # the state file, so we can go ahead and write it out.
	$self->_store_config ($self);
    }
    elsif ($self->{modified}) {
        # We don't have the giant lock, but we do have something to
        # change, so get the lock, read in the current state, merge in
        # the changes from the paths we locked, and write it out.
	$self->giant_lock ();
	my $info = LoadFile ($self->{statefile});
	$info->{checkout} = $info->{checkout}->to_absolute($self->{floating})
	    if $self->{floating};
	my @paths = $info->{checkout}->find ('', {lock => $$});
	$info->{checkout}->merge ($self->{checkout}, $_)
	    for @paths;
        $self->_store_config($info);
    }
    $self->giant_unlock ();
}

=item lock

Lock the given checkout path, store the state with the lock info to
prevent other instances from modifying locked paths.

=cut

sub lock {
    my ($self, $path) = @_;
    if ($self->{checkout}->get ($path, 1)->{lock}) {
	die loc("%1 already locked, use 'svk cleanup' if lock is stalled\n", $path);
    }
    $self->{checkout}->store ($path, {lock => $$});
    $self->{modified} = 1;
}

=item unlock

Unlock all the checkout paths that were locked by this instance.

=cut

sub unlock {
    my ($self) = @_;
    my @paths = $self->{checkout}->find ('', {lock => $$});
    $self->{checkout}->store ($_, {lock => undef})
	for @paths;
}

=item giant_lock

Lock the statefile globally. All other instances need to wait for the
lock before they can do anything.

=cut

sub giant_lock {
    my ($self) = @_;
    return unless $self->{giantlock};
    my $lock_handle;

    my $DIE = sub { my $verb = shift; die "can't $verb giant lock ($self->{giantlock}): $!\n" };

    LOCKED: {
        for (1..5) {
            open($lock_handle, '>>', $self->{giantlock}) or $DIE->('open');

            # Try to get an exclusive lock; don't block
            my $success = flock $lock_handle, LOCK_EX | LOCK_NB;
            last LOCKED if $success;

            # Somebody else has it locked; try again in a second.
            close($lock_handle);
            sleep 1;
        }

        $self->{updated} = 1;
        die loc("Another svk might be running; remove %1 if not.\n", $self->{giantlock});
    }

    # We've got the lock. For diagnostic purposes, write out our PID.
    seek($lock_handle, 0, 0) or $DIE->('rewind');
    truncate($lock_handle, 0) or $DIE->('truncate');
    $lock_handle->autoflush(1);
    (print $lock_handle $$) or $DIE->('write');

    $self->{giantlock_handle} = $lock_handle;
}

=item giant_unlock

Release the giant lock.

=back

=cut

sub giant_unlock {
    my ($self) = @_;
    return unless $self->{giantlock} and $self->{giantlock_handle};

    close $self->{giantlock_handle};
    unlink ($self->{giantlock});
    delete $self->{giantlock_handle};
}

=head2 Depot and path translation

=over

=cut

my %REPOS;
my $REPOSPOOL = SVN::Pool->new;

sub _open_repos {
    my ($repospath) = @_;
    $REPOS{$repospath} ||= SVN::Repos::open ($repospath, $REPOSPOOL);
}

=item find_repos

Given depotpath and an option about if the repository should be
opened. Returns an array of repository path, the path inside
repository, and the C<SVN::Repos> object if caller wants the
repository to be opened.

=cut

# DEPRECATED
sub find_repos {
    my ($self, $depotpath, $open) = @_;
    die loc("no depot spec") unless $depotpath;
    my ($depot, $path) = $depotpath =~ m|^/([^/]*)(/.*?)/?$|
	or die loc("%1 is not a depot path.\n", $depotpath);

    $path = Path::Class::foreign_dir('Unix', $path)->stringify;
    my $repospath = $self->{depotmap}{$depot} or die loc("No such depot: %1.\n", $depot);

    return ($repospath, $path, $open && _open_repos ($repospath));
}

sub find_depotpath {
    my ($self, $depotpath) = @_;
    die loc("no depot spec") unless $depotpath;
    my ($depotname, $path) = $depotpath =~ m|^/([^/]*)(/.*?)/?$|
	or die loc("%1 is not a depot path.\n", $depotpath);
    $path = Path::Class::foreign_dir('Unix', $path)->stringify;

    return ( $self->find_depot($depotname), $path );
}

sub find_depot {
    my ($self, $depotname) = @_;
    my $repospath = $self->{depotmap}{$depotname} or die loc("No such depot: %1.\n", $depotname);

    return SVK::Depot->new( { depotname => $depotname,
                              repospath => $repospath,
                              repos => _open_repos($repospath) } );
}

=item find_repos_from_co

Given the checkout path and an option about if the repository should
be opened. Returns an array of repository path, the path inside
repository, the absolute checkout path, the checkout info, and the
C<SVN::Repos> object if caller wants the repository to be opened.

=cut

sub find_repos_from_co {
    my ($self, $copath, $open) = @_;
    my $report = $copath;
    $copath = abs_path (File::Spec->canonpath ($copath));
    die loc("path %1 is not a checkout path.\n", $report)
	unless $copath;
    my ($cinfo, $coroot) = $self->{checkout}->get ($copath);
    die loc("path %1 is not a checkout path.\n", $copath) unless %$cinfo;
    my ($repospath, $path, $repos) = $self->find_repos ($cinfo->{depotpath}, $open);

    return ($repospath, abs2rel ($copath, $coroot => $path, '/'), $copath,
	    $cinfo, $repos);
}

=item find_repos_from_co_maybe

Like C<find_repos_from_co>, but falls back to see if the given path is
a depotpath. In that case, the checkout paths returned will be undef.

=cut

sub find_repos_from_co_maybe {
    my ($self, $target, $open) = @_;
    my ($repospath, $path, $copath, $cinfo, $repos);
    if (($repospath, $path, $repos) = eval { $self->find_repos ($target, $open) }) {
	return ($repospath, $path, undef, undef, $repos);
    }
    undef $@;
    return $self->find_repos_from_co ($target, $open);
}

=item find_depotname

=cut

sub find_depotname {
    my ($self, $target, $can_be_co) = @_;
    my ($cinfo);
    local $@;
    if ($can_be_co) {
	(undef, undef, $cinfo) = eval { $self->find_repos_from_co ($target, 0) };
	$target = $cinfo->{depotpath} unless $@;
    }

    $self->find_repos ($target, 0);
    return ($target =~ m|^/(.*?)/|);
}

=back

=cut

sub target_condensed {
    my ($self, @paths) = @_;
    return unless @paths;
    my $anchor;
    for my $path (@paths) {
	unless (defined $anchor) {
	    $anchor = $path->clone;
	    $anchor->copath_anchor(Path::Class::dir($anchor->copath_anchor));
	}
	my ($cinfo, $schedule) = $self->get_entry($anchor->copath_anchor, 1);
	while ($cinfo->{scheduleanchor} || !-d $anchor->copath_anchor ||
	       $schedule eq 'add' || $schedule eq 'delete' || $schedule eq 'replace' ||
	       !( $anchor->copath_anchor->subsumes($path->copath_anchor)) ) {
	    $anchor->anchorify;
	    $anchor->copath_anchor(Path::Class::dir($anchor->copath_anchor));
	    ($cinfo, $schedule) = $self->get_entry($anchor->copath_anchor, 1);
	}
	push @{$anchor->source->{targets}}, abs2rel($path->copath, $anchor->copath => undef, '/') unless $anchor->path eq $path->path;
    }

    my $root = $anchor->create_xd_root;
    until ($root->check_path($anchor->path_anchor) == $SVN::Node::dir) {
	$anchor->anchorify;
    }

    delete $anchor->{cinfo};
    return $anchor;
}

# simliar to command::arg_copath, but still return a target when
# basepath doesn't exist, arg_copath should be gradually deprecated
sub target_from_copath_maybe {
    my ($self, $arg) = @_;

    my $rev = $arg =~ s/\@(\d+)$// ? $1 : undef;
    my ($repospath, $path, $depotpath, $copath, $repos, $view);
    unless (($repospath, $path, $repos) = eval { $self->find_repos ($arg, 1) }) {
	$arg = File::Spec->canonpath($arg);
	$copath = abs_path_noexist($arg);
	my ($cinfo, $coroot) = $self->{checkout}->get ($copath);
	die loc("path %1 is not a checkout path.\n", $copath) unless %$cinfo;
	($repospath, $path, $repos) = $self->find_repos ($cinfo->{depotpath}, 1);
	my ($rev, $subpath);
	if (($view, $rev, $subpath) = $path =~ m{^/\^([\w/\-_]+)(?:\@(\d+)(.*))?$}) {
	    ($path, $view) = SVK::Command->create_view ($repos, $view, $rev, $subpath);
	}

	$path = abs2rel ($copath, $coroot => $path, '/');

	($depotpath) = $cinfo->{depotpath} =~ m|^/(.*?)/|;
	$depotpath = "/$depotpath$path";
    }

    from_native ($path, 'path', $self->{encoding});
    undef $@;
    my $ret = $self->create_path_object
	( repos => $repos,
	  repospath => $repospath,
	  depotpath => $depotpath || $arg,
	  copath_anchor => $copath,
	  report => $arg,
	  path => $path,
	  view => $view,
	  revision => $rev,
	);
    $ret = $ret->as_depotpath unless defined $copath;
    return $ret;
}

sub create_path_object {
    my ($self, %arg) = @_;
    if (my $depotpath = delete $arg{depotpath}) {
	($arg{depotname}) = $depotpath =~ m!^/([^/]*)!;
    }

    if (defined (my $copath = delete $arg{copath_anchor})) {
	require SVK::Path::Checkout;
	my $report = delete $arg{report};
	return SVK::Path::Checkout->real_new
	    ({ xd => $self,
	       report => $report,
	       copath_anchor => $copath,
	       source => $self->create_path_object(%arg) });
    }

    my $path;
    unless ($arg{depot}) {
        my $depotname = delete $arg{depotname};
        my $repospath = delete $arg{repospath};
        my $repos     = delete $arg{repos};
        $arg{depot} = SVK::Depot->new({ depotname => $depotname, repos => $repos, repospath => $repospath });
    }
    if (defined (my $view = delete $arg{view})) {
	require SVK::Path::View;
        $path = SVK::Path::View->real_new
	    ({ source => $self->create_path_object(%arg),
	       view => $view,
	       %arg });
    }
    else {
	$path = SVK::Path->real_new(\%arg);
    }

    $path->refresh_revision unless defined $path->revision;
    return $path;
}

=head2 Checkout handling

=over

=item auto_prop

Return a hash of properties that should attach to the file
automatically when added.

=cut

sub _load_svn_autoprop {
    my $self = shift;
    $self->{svnautoprop} = {};
    local $@;
    eval {
        SVK::Config->svnconfig->{config}->
	    enumerate ('auto-props',
		       sub { $self->{svnautoprop}{compile_apr_fnmatch($_[0])} = $_[1]; 1} );
    };
    $logger->warn("Your svn is too old, auto-prop in svn config is not supported: $@") if $@;
}

sub auto_prop {
    my ($self, $copath) = @_;

    # no other prop for links
    return {'svn:special' => '*'} if is_symlink($copath);
    my $prop;
    $prop->{'svn:executable'} = '*' if is_executable($copath);

    # auto mime-type: binary or text/* but not text/plain
    if ( my $type = mimetype($copath) ) {
        $prop->{'svn:mime-type'} = $type
            if $type ne 'text/plain'
            && ( $type =~ m/^text/ || !mimetype_is_text($type) );
    }

    # svn auto-prop
    if (SVK::Config->svnconfig && SVK::Config->svnconfig->{config}->get_bool ('miscellany', 'enable-auto-props', 0)) {
	$self->_load_svn_autoprop unless $self->{svnautoprop};
	my (undef, undef, $filename) = splitpath ($copath);
	while (my ($pattern, $value) = each %{$self->{svnautoprop}}) {
	    next unless $filename =~ m/$pattern/;
	    for (split (/\s*;\s*/, $value)) {
		my ($propname, $propvalue) = split (/\s*=\s*/, $_, 2);
		$prop->{$propname} = $propvalue;
	    }
	}
    }
    return $prop;
}

sub do_delete {
    my ($self, $target, %arg) = @_;
    my (@deleted, @modified, @unknown, @scheduled);

    $target->anchorify unless $target->source->{targets};

    # check for if the file/dir is modified.
    $target->run_delta(
        SVK::Editor::Status->new(
            notify => SVK::Notify->new(
                cb_flush => sub {
                    my ( $path, $status ) = @_;
                    my $copath = $target->copath($path);
                    $target->contains_copath($copath) or return;

                    my $st = $status->[0];
                    if ( $st eq 'M' ) {
                        push @modified, $copath;
                    } elsif ( $st eq 'D' ) {
                        push @deleted, $copath;
                    } else {
                        push @scheduled, $copath;
                    }
                }
            )
        ),
        {   %arg,  # current callers args: quiet, no_rm, force_delete
            absent_as_delete => 1,
            delete_verbose   => 1,
            absent_verbose   => 1,
            cb_unknown       => sub {
                push @unknown, $target->copath( $_[1] );
                }
        }
    );

    # use Data::Dumper; warn Dumper \@unknown, \@modified, \@scheduled;
    unless ($arg{force_delete}) {
    	my @reports;
	push @reports, sort map { loc("%1 is not under version control", $target->report_copath($_)) } @unknown;
	push @reports, sort map { loc("%1 is modified", $target->report_copath($_)) } @modified;
	push @reports, sort map { loc("%1 is scheduled", $target->report_copath($_)) } @scheduled;

	die join(",\n", @reports) . "; use '--force' to go ahead.\n"
	    if @reports;
    }

    # actually remove it from checkout path
    my @paths = grep {is_symlink($_) || -e $_} $target->copath_targets;
    
    my $ignore = $self->ignore;
    find(sub {
	     return if m/$ignore/;
	     my $cpath = catdir($File::Find::dir, $_);
	     no warnings 'uninitialized';
	     return if $self->{checkout}->get($cpath, 1)->{'.schedule'}
		 eq 'delete';

	     push @deleted, $cpath; 
	 }, @paths) if @paths;


    my %noschedule = map { $_ => 1 } (@unknown, @scheduled);
    for (@deleted) {
	print "D   ".$target->report_copath($_)."\n"
	    unless $arg{quiet};
	
	# don't schedule unknown/added files for deletion as this confuses revert.    
	$self->{checkout}->store ($_, {'.schedule' => 'delete'})
	    unless $noschedule{$_};
    }
   
    if (@scheduled) {
    	# XXX - should we report something?
	require SVK::Command;
	$self->{checkout}->store ($_, { SVK::Command->_schedule_empty })
	    for @scheduled;
    }

    # TODO: perhaps use the information to warn commiting a rename partially
    $self->{checkout}->store($_, {scheduleanchor => $_})
	for $target->copath_targets;
    
    return if $arg{no_rm};
    rmtree (\@paths) if @paths;
}

sub do_propset {
    my ($self, $target, %arg) = @_;
    my ($entry, $schedule) = $self->get_entry($target->copath);
    $entry->{'.newprop'} ||= {};

    unless ( $schedule eq 'add' ) {
        my $xdroot = $target->create_xd_root;
        my ( $source_path, $source_root )
            = $self->_copy_source( $entry, $target->copath, $xdroot );
        $source_path ||= $target->path_anchor;
        $source_root ||= $xdroot;
        die loc( "%1 is not under version control.\n", $target->report )
            if $xdroot->check_path($source_path) == $SVN::Node::none;
    }

    #XXX: support working on multiple paths and recursive
    die loc("%1 is already scheduled for delete.\n", $target->report)
	if $schedule eq 'delete';
    my %values = %{$entry->{'.newprop'}}
	if exists $entry->{'.schedule'};
    my $pvalue = defined $arg{propvalue} ? $arg{propvalue} : \undef;

    $self->{checkout}->store ($target->copath,
			      { '.schedule' => $schedule || 'prop',
				'.newprop' => {%values,
					    $arg{propname} => $pvalue
					      }});
    print " M  ".$target->report."\n" unless $arg{quiet};

    $self->fix_permission($target->copath, $arg{propvalue})
	if $arg{propname} eq 'svn:executable';
}

sub fix_permission {
    my ($self, $copath, $value) = @_;
    my $mode = (stat ($copath))[2];
    if (defined $value) {
	$mode |= 0111;
    }
    else {
	$mode &= ~0111;
    }
    chmod ($mode, $copath);
}

=item depot_delta

Generate C<SVN::Delta::Editor> calls to represent the changes between
C<(oldroot, oldpath)> and C<(newroot, newpath)>. oldpath is a array
ref for anchor and target, newpath is just a string.

Options:

=over

=item editor

The editor receiving delta calls.

=item no_textdelta

Don't generate text deltas in C<apply_textdelta> calls.

=item no_recurse

=item notice_ancestry

=back

=cut

sub depot_delta {
    my ($self, %arg) = @_;
    my @root = map {$_->isa ('SVK::Root') ? $_->root : $_} @arg{qw/oldroot newroot/};
    my $editor = $arg{editor};
    SVN::Repos::dir_delta ($root[0], @{$arg{oldpath}},
			   $root[1], $arg{newpath},
			   $editor, undef,
			   $arg{no_textdelta} ? 0 : 1,
			   $arg{no_recurse} ? 0 : 1,
			   0, # we never need entry props
			   $arg{notice_ancestry} ? 0 : 1,
			   $arg{pool});
}

=item checkout_delta

Generate C<SVN::Delta::Editor> calls to represent the local changes
made to the checked out revision.

Options:

=over

=item delete_verbose

Generate delete_entry calls for sub-entries within deleted entry.

=item absent_verbose

Generate absent_* calls for sub-entries within absent entry.

=item unknown_verbose

generate cb_unknown calls for sub-entries within absent entry.

=item absent_ignore

Don't generate absent_* calls.

=item expand_copy

Mimic the behavior like SVN::Repos::dir_delta, lose copy information
and treat all copied descendents as added too.

=item cb_ignored

Called for ignored items if defined.

=item cb_unchanged

Called for unchanged files if defined.

=back

=cut

my %ignore_cache;

sub ignore {
    my $self = shift;
    my $more_ignores = shift;

    no warnings;
    my $ignore = SVK::Config->svnconfig ?
	           SVK::Config->svnconfig->{config}->
		   get('miscellany', 'global-ignores', '') : '';
    my @ignore = split / /,
	($ignore || "*.o *.lo *.la #*# .*.rej *.rej .*~ *~ .#* .DS_Store");
    push @ignore, 'svk-commit*.tmp';
    push @ignore, @{$self->{ignore}}
	if $self->{ignore};

    if (defined $more_ignores) {
        push @ignore, split ("\n", $more_ignores);
    }

    return join('|', map {$ignore_cache{$_} ||= compile_apr_fnmatch($_)} (@ignore));
}

require SVK::DeltaOld;
sub checkout_delta {
    goto \&SVK::DeltaOld::checkout_delta;
}

=item get_entry($copath)

Returns the L<Data::Hierarchy> entry and the schedule of the entry.

=cut

sub get_entry {
    my ($self, $copath, $dont_clone) = @_;
    my $entry = $self->{checkout}->get($copath, $dont_clone);
    return ($entry, $entry->{'.schedule'} || '');
}

sub resolved_entry {
    my ($self, $entry) = @_;
    my $val = $self->{checkout}->get ($entry, 1);
    return unless $val && $val->{'.conflict'};
    $self->{checkout}->store ($entry, {%$val, '.conflict' => undef});
    $logger->warn(loc("%1 marked as resolved.", $entry));
}

sub do_resolved {
    my ($self, %arg) = @_;

    if ($arg{recursive}) {
	for ($self->{checkout}->find ($arg{copath}, {'.conflict' => 1})) {
	    $self->resolved_entry ($_);
	}
    }
    else {
	$self->resolved_entry ($arg{copath});
    }
}

sub get_eol_layer {
    my ($prop, $mode, $checkle) = @_;
    my $k = $prop->{'svn:eol-style'} or return ':raw';
    # short-circuit no-op write layers on lf platforms
    if (NATIVE eq LF) {
	return ':raw' if $mode eq '>' && ($k eq 'native' or $k eq 'LF');
    }
    # XXX: on write we should actually be notified when it's to be
    # normalized.
    if ($k eq 'native') {
	$checkle = $checkle ? '!' : '';
        return ":raw:eol(LF$checkle-Native)";
    }
    elsif ($k eq 'CRLF' or $k eq 'CR' or $k eq 'LF') {
	$k .= '!' if $checkle;
        return ":raw:eol($k)";
    }
    else {
        return ':raw'; # unsupported
    }
}

# Remove anything from the keyword value that could prevent us from being able
# to correctly collapse it again later.
sub _sanitize_keyword_value {
    my $value = shift;
    $value =~ s/[\r\n]/ /g;
    $value =~ s/ +\$/\$/g;
    return $value;
}

sub get_keyword_layer {
    my ($root, $path, $prop) = @_;
    my $k = $prop->{'svn:keywords'};
    return unless $k;

    # XXX: should these respect svm related stuff
    my %kmap = ( Date =>
		 sub { my ($root, $path) = @_;
		       my $rev = $root->node_created_rev ($path);
		       my $fs = $root->fs;
		       $fs->revision_prop ($rev, 'svn:date');
		   },
		 Rev =>
		 sub { my ($root, $path) = @_;
		       $root->node_created_rev ($path);
		 },
		 Author =>
		 sub { my ($root, $path) = @_;
		       my $rev = $root->node_created_rev ($path);
		       my $fs = $root->fs;
		       $fs->revision_prop ($rev, 'svn:author');
		 },
		 Id =>
		 sub { my ($root, $path) = @_;
		       my $rev = $root->node_created_rev ($path);
		       my $fs = $root->fs;
		       join( ' ', $path, $rev,
			     $fs->revision_prop ($rev, 'svn:date'),
			     $fs->revision_prop ($rev, 'svn:author'), ''
			   );
		   },
		 URL =>
		 sub { my ($root, $path) = @_;
		       return $path;
		   },
		 FileRev =>
		 sub { my ($root, $path) = @_;
		       my $rev = 0;
		       traverse_history ( root     => $root,
					  path     => $path,
					  cross    => 0,
					  callback => sub { ++$rev });
		       "#$rev";
		   },
	       );
    my %kalias = qw(
	LastChangedDate	    Date
	LastChangedRevision Rev
	LastChangedBy	    Author
	HeadURL		    URL

	Change		    Rev
	File		    URL
	DateTime	    Date
	Revision	    Rev
	FileRevision	    FileRev
    );

    $kmap{$_} = $kmap{$kalias{$_}} for keys %kalias;

    my %key = map { ($_ => 1) } grep {exists $kmap{$_}} (split /\W+/,$k);
    return unless %key;
    while (my ($k, $v) = each %kalias) {
	$key{$k}++ if $key{$v};
	$key{$v}++ if $key{$k};
    }

    my $keyword = '('.join('|', sort keys %key).')';

    return PerlIO::via::dynamic->new
	(translate =>
         sub { $_[1] =~ s/\$($keyword)(?:: .*? )?\$/"\$$1: "._sanitize_keyword_value($kmap{$1}->($root, $path)).' $'/eg; },
	 untranslate =>
	 sub { $_[1] =~ s/\$($keyword)(?:: .*? )?\$/\$$1\$/g; });
}

sub _fh_symlink {
    my ($mode, $fname) = @_;
    my $fh;
    if ($mode eq '>') {
        open $fh, '>:via(symlink)', $fname;
    }
    elsif ($mode eq '<') {
	# XXX: make PerlIO::via::symlink also do the reading
        open $fh, '<', \("link ".readlink($fname));
    }
    else {
        die "unknown mode $mode for symlink fh";
    }
    return $fh;
}

=item get_fh

Returns a file handle with keyword translation and line-ending layers attached.

=cut

sub get_fh {
    my ($root, $mode, $path, $fname, $prop, $layer, $eol) = @_;
    {
        # don't care about nonexisting path, for new file with keywords
        local $@;
        $prop ||= eval { $root->node_proplist($path) } || {};
    }
    use Carp; Carp::cluck unless ref $prop eq 'HASH';
    return _fh_symlink ($mode, $fname)
	   if HAS_SYMLINK and ( defined $prop->{'svn:special'} || ($mode eq '<' && is_symlink($fname)) );
    if (keys %$prop) {
        $layer ||= get_keyword_layer ($root, $path, $prop);
        $eol ||= get_eol_layer($prop, $mode);
    }
    $eol ||= ':raw';
    open my ($fh), $mode.$eol, $fname or return undef;
    $layer->via ($fh) if $layer;
    return $fh;
}

=item get_props

Returns the properties associated with a node. Properties schedule for
commit are merged if C<$copath> is given.

=back

=cut

sub _combine_prop {
    my ($props, $newprops) = @_;
    return $props unless $newprops;
    $props = {%$props, %$newprops};
    for (keys %$props) {
	delete $props->{$_}
	    if ref ($props->{$_}) && !defined ${$props->{$_}};
    }
    return $props;
}

sub _copy_source {
    my ($self, $entry, $copath, $root) = @_;
    return unless $entry->{scheduleanchor};
    my $descendent = abs2rel($copath, $entry->{scheduleanchor}, '', '/');
    $entry = $self->{checkout}->get ($entry->{scheduleanchor}, 1)
	if $entry->{scheduleanchor} ne $copath;
    my $from = $entry->{'.copyfrom'} or return;
    $from .= $descendent;
    return ($from, $root ? $root->fs->revision_root ($entry->{'.copyfrom_rev'})
	    : $entry->{'.copyfrom_rev'});
}

sub get_props {
    my ($self, $root, $path, $copath, $entry) = @_;
    my $props = {};
    $entry ||= $self->{checkout}->get ($copath, 1) if $copath;
    my $schedule = $entry->{'.schedule'} || '';

    if (my ($source_path, $source_root) = $self->_copy_source ($entry, $copath, $root)) {
	$props = $source_root->node_proplist ($source_path);
    }
    elsif ($schedule ne 'add' && $schedule ne 'replace') {
	Carp::cluck 'hate' unless defined $path;
	$props = $root->node_proplist($path);
    }
    return _combine_prop ($props, $entry->{'.newprop'});
}

sub cache_directory {
    my ($self) = @_;
    my $rv = catdir ( $self->{svkpath}, 'cache' );
    mkdir $rv or die $! unless -e $rv;
    return $rv;
}

sub patch_directory {
    my ($self) = @_;
    my $rv = catdir ( $self->{svkpath}, 'patch' );
    mkdir $rv or die $! unless -e $rv;
    return $rv;
}

sub patch_file {
    my ($self, $name) = @_;
    return '-' if $name eq '-';
    return catdir ($self->patch_directory, "$name.patch");
}

sub DESTROY {
    my ($self) = @_;
    return if $self->{updated};
    $self->store ();
}

package SVK::XD::Signature;
use SVK::Util qw( $SEP );

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, __PACKAGE__;
    %$self = @arg;
    mkdir ($self->{root}) or die $! unless -e $self->{root};
    return $self;
}

sub load {
    my ($factory, $path) = @_;
    my $spath = $path;

    if ($factory->{floating}) {
	$spath .= $SEP if $spath eq $factory->{floating};
	$spath = substr($spath, length($factory->{floating}));
    }

    $spath =~ s{(?=[_=])}{=}g;
    $spath =~ s{:}{=-}g;
    $spath =~ s{\Q$SEP}{_}go;
    my $self = bless { root => $factory->{root},
		       floating => $factory->{floating},
		       path => $path, spath => $spath }, __PACKAGE__;
    $self->read;
    return $self;
}

sub path {
    my $self = shift;
    return "$self->{root}$SEP$self->{spath}";
}

sub lock_path {
    my $self = shift;
    return $self->path.'=lock';
}

sub lock {
    my ($self) = @_;
    my $path = $self->lock_path;
    return if -e $path;
    open my $fh, '>', $path or warn $!, return;
    print $fh $$;
    $self->{locked} = 1;
}

sub unlock {
    my ($self) = @_;
    my $path = $self->lock_path;
    unlink $path if -e $path;
    $self->{locked} = 0;
}

sub read {
    my ($self) = @_;
    my $path = $self->path;
    if (-s $path) {
        open my $fh, '<:raw', $path or die $!;
        $self->{signature} =  { <$fh> };
    }
    else {
        $self->{signature} = {};
    }

    $self->{changed} = {};
    $self->{newsignature} = {};
}

sub write {
    my ($self) = @_;
    my $path = $self->path;
    # nothing to write
    return unless keys %{$self->{changed}};

    $self->lock;
    return unless $self->{locked};
    my ($hash, $file) = @_;
    open my $fh, '>:raw', $path or die $!;
    print {$fh} $self->{keepold} ? (%{$self->{signature}}, %{$self->{newsignature}})
	: %{ $self->{newsignature} };
    $self->unlock;
}

sub changed {
    my ($self, $entry) = @_;
    my $file = "$self->{path}/$entry";
    # inode, mtime, size
    my @sig = (stat ($file))[1,7,9] or return 1;

    my ($key, $value) = (quotemeta($entry)."\n", "@sig\n");
    my $changed = (!exists $self->{signature}{$key} ||
		   $self->{signature}{$key} ne $value);
    $self->{changed}{$key} = 1 if $changed;
    delete $self->{signature}{$key};
    $self->{newsignature}{$key} = $value
	if !$self->{keepold} || $changed;

    return $changed;
}

sub invalidate {
    my ($self, $entry) = @_;
    my $key = quotemeta($entry)."\n";
    delete $self->{newsignature}{$key};
    delete $self->{changed}{$key};
}

sub flush {
    my ($self) = @_;
    $self->write;
}

1;
