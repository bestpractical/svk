package SVK::XD;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;

use SVK::I18N;
use SVK::Util qw( get_anchor abs_path abs_path_noexist abs2rel splitdir catdir splitpath $SEP
		  HAS_SYMLINK is_symlink is_executable mimetype mimetype_is_text
		  md5_fh get_prompt traverse_history make_path dirname
		  from_native to_native get_encoder get_depot_anchor );
use Data::Hierarchy 0.30;
use autouse 'File::Find' => qw(find);
use autouse 'File::Path' => qw(rmtree);
use autouse 'YAML::Syck'	 => qw(LoadFile DumpFile);
use SVK::Mirror;
use PerlIO::eol 0.10 qw( NATIVE LF );
use PerlIO::via::dynamic;
use PerlIO::via::symlink;
use Class::Autouse qw( Path::Class SVK::Editor::Delay );

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

A filename for global locking.

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
	    print loc ("Can't load statefile, old statefile saved as %1\n",
		     "$self->{statefile}.backup");
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

        make_path(dirname($path));

        $ENV{SVNFSTYPE} ||= (($SVN::Core::VERSION =~ /^1\.0/) ? 'bdb' : 'fsfs');
	SVN::Repos::create($path, undef, undef, undef,
			   {'fs-type' => $ENV{SVNFSTYPE},
			    'bdb-txn-nosync' => '1',
			    'bdb-log-autoremove' => '1'});
    }
    return;
}


=item store

Serialize C<$self> to the statefile. If giant lock is still ours,
overwrite the file directly. Otherwise load the file again and merge
the paths we locked into the new state file. After C<store> is called,
giant is unlocked.

=cut

sub _store_config {
    my ($self, $hash) = @_;
    local $SIG{INT} = sub { warn loc("Please hold on a moment. SVK is writing out a critical configuration file.\n")};

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
	die loc("Couldn't remove your old backup configuration file %1 while writing the new one.", $oldfile);
    }
    if (-f $file ) {
        rename ($file => $oldfile) ||
        	die loc("Couldn't remove your old configuration file %1 while writing the new one.", $file);
    }
    rename ($tmpfile => $file) ||
	die loc("Couldn't write your new configuration file %1. A backup has been stored in %2. Please replace %1 with %2 immediately.", $file, $tmpfile);

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
    if ($self->{giantlocked}) {
	$self->_store_config ($self);
    }
    elsif ($self->{modified}) {
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
prevent other instances from modifying locked paths. The giant lock is
released afterward.

=cut

sub lock {
    my ($self, $path) = @_;
    if ($self->{checkout}->get ($path)->{lock}) {
	die loc("%1 already locked, use 'svk cleanup' if lock is stalled\n", $path);
    }
    $self->{checkout}->store ($path, {lock => $$});
    $self->{modified} = 1;
    $self->_store_config($self) if $self->{statefile};
    $self->giant_unlock ();
}

=item unlock

Unlock All the checkout paths that was locked by this instance.

=cut

sub unlock {
    my ($self) = @_;
    my @paths = $self->{checkout}->find ('', {lock => $$});
    $self->{checkout}->store ($_, {lock => undef})
	for @paths;
}

=item giant_lock

Lock the statefile globally. No other instances need to wait for the
lock before they can do anything.

=cut

sub giant_lock {
    my ($self) = @_;
    return unless $self->{giantlock};

    LOCKED: {
        for (1..5) {
            -e $self->{giantlock} or last LOCKED;
            sleep 1;
        }

        $self->{updated} = 1;
        die loc("Another svk might be running; remove %1 if not.\n", $self->{giantlock});
    }

    open my ($lock), '>', $self->{giantlock}
	or die loc("Cannot acquire giant lock %1:%2.\n", $self->{giantlock}, $!);
    print $lock $$;
    close $lock;
    $self->{giantlocked} = 1;
}

=item giant_unlock

Release the giant lock.

=back

=cut

sub giant_unlock {
    my ($self) = @_;
    return unless $self->{giantlock};
    unlink ($self->{giantlock});
    delete $self->{giantlocked};
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

sub find_repos {
    my ($self, $depotpath, $open) = @_;
    die loc("no depot spec") unless $depotpath;
    my ($depot, $path) = $depotpath =~ m|^/([^/]*)(/.*?)/?$|
	or die loc("%1 is not a depot path.\n", $depotpath);

    $path = Path::Class::foreign_dir('Unix', $path)->stringify;
    my $repospath = $self->{depotmap}{$depot} or die loc("No such depot: %1.\n", $depot);

    return ($repospath, $path, $open && _open_repos ($repospath));
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
a depotpath. In that case, the checkout paths returned iwll be undef.

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
	my ($cinfo, $schedule) = $self->get_entry($anchor->copath_anchor);
	while ($cinfo->{scheduleanchor} || !-d $anchor->copath_anchor ||
	       $schedule eq 'add' || $schedule eq 'delete' || $schedule eq 'replace' ||
	       !( $anchor->copath_anchor->subsumes($path->copath_anchor)) ) {
	    $anchor->anchorify;
	    $anchor->copath_anchor(Path::Class::dir($anchor->copath_anchor));
	    ($cinfo, $schedule) = $self->get_entry($anchor->copath_anchor);
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
    $arg{mirror} ||= $self->mirror($arg{repos});

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

sub xdroot {
    SVK::XD::Root->new (create_xd_root (@_));
}

sub create_xd_root {
    my ($self, %arg) = @_;
    Carp::confess unless $arg{repos};
    my ($fs, $copath) = ($arg{repos}->fs, $arg{copath});
    $copath = File::Spec::Unix->catdir($copath, $arg{copath_target})
	if defined $arg{copath_target};
    my ($txn, $root);

    my @paths = $self->{checkout}->find ($copath, {revision => qr'.*'});

    # In the simple case - only one revision entry found, it can be
    # for some descendents.  If so we actually need to construct
    # txnroot.
    my ($simple, @bases) = $self->{checkout}->get($paths[0] || $copath);
    # XXX this isn't really right: we aren't guaranteed that $revbase
    # actually has the revision, it might just have a lock or
    # something
    my $revbase = $bases[-1];
    unshift @paths, $revbase unless $revbase eq $copath;
    return (undef, $fs->revision_root($simple->{revision}))
	if $#paths <= 0;

    my $pool = SVN::Pool->new;
    for (@paths) {
	my $cinfo = $self->{checkout}->get ($_);
	my $path = abs2rel($_, $copath => $arg{path}, '/');
	unless ($root) {
	    my $base_rev = $cinfo->{revision};
	    $txn = $fs->begin_txn ($base_rev, $arg{pool});
	    $root = $txn->root($arg{pool});
	    if ($base_rev == 0) {
		# for interrupted checkout, the anchor will be at rev 0
		my @path = ();
		for my $dir (File::Spec::Unix->splitdir($path)) {
		    push @path, $dir;
		    next unless length $dir;
		    $root->make_dir(File::Spec::Unix->catdir(@path));
		}
	    }
	    next;
	}
	my ($parent) = get_anchor(0, $path);
	next if $cinfo->{revision} == $root->node_created_rev($parent, $pool);
	$root->delete ($path, $pool)
	    if eval { $root->check_path ($path, $pool) != $SVN::Node::none };
	SVN::Fs::revision_link ($fs->revision_root ($cinfo->{revision}, $pool),
				$root, $path, $pool)
		unless $cinfo->{'.deleted'};
	$pool->clear;
    }
    return ($txn, $root);
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
	$self->{svnconfig}{config}->
	    enumerate ('auto-props',
		       sub { $self->{svnautoprop}{compile_apr_fnmatch($_[0])} = $_[1]; 1} );
    };
    warn "Your svn is too old, auto-prop in svn config is not supported: $@\n" if $@;
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
    if ($self->{svnconfig} && $self->{svnconfig}{config}->get_bool ('miscellany', 'enable-auto-props', 0)) {
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
    $self->checkout_delta ( $target->for_checkout_delta,
			    %arg,
			    xdroot => $target->create_xd_root,
			    absent_as_delete => 1,
			    delete_verbose => 1,
			    absent_verbose => 1,
			    editor => SVK::Editor::Status->new
			    ( notify => SVK::Notify->new
			      ( cb_flush => sub {
				    my ($path, $status) = @_;
				    my $copath = $target->copath($path);
				    $target->contains_copath($copath) or return;

				    my $st = $status->[0];
				    if ($st eq 'M') {
				    	push @modified, $copath;
				    }
				    elsif ($st eq 'D') {
					push @deleted, $copath;
				    }
				    else {
					push @scheduled, $copath;
				    }
				})),
			    cb_unknown => sub {
			    	push @unknown, $target->copath($_[1]);
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
	     return if $self->{checkout}->get ($cpath)->{'.schedule'}
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
    my ($self, %arg) = @_;
    my ($xdroot, %values);
    my ($entry, $schedule) = $self->get_entry($arg{copath});
    $entry->{'.newprop'} ||= {};

    unless ($schedule eq 'add' || !$arg{repos}) {
	$xdroot = $self->xdroot (%arg);
	my ($source_path, $source_root) = $self->_copy_source ($entry, $arg{copath}, $xdroot);
	$source_path ||= $arg{path}; $source_root ||= $xdroot;
	die loc("%1 is not under version control.\n", $arg{report})
	    if $xdroot->check_path ($source_path) == $SVN::Node::none;
    }

    #XXX: support working on multiple paths and recursive
    die loc("%1 is already scheduled for delete.\n", $arg{report})
	if $schedule eq 'delete';
    %values = %{$entry->{'.newprop'}}
	if exists $entry->{'.schedule'};
    my $pvalue = defined $arg{propvalue} ? $arg{propvalue} : \undef;

    $self->{checkout}->store ($arg{copath},
			      { '.schedule' => $schedule || 'prop',
				'.newprop' => {%values,
					    $arg{propname} => $pvalue
					      }});
    print " M  $arg{report}\n" unless $arg{quiet};

    $self->fix_permission ($arg{copath}, $arg{propvalue})
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

# XXX: checkout_delta is getting too complicated and too many options
my %ignore_cache;

sub ignore {
    my $self = shift;
    my $more_ignores = shift;

    no warnings;
    my $ignore = $self->{svnconfig} ?
	           $self->{svnconfig}{config}->
		   get ('miscellany', 'global-ignores', '') : '';
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

# Emulates APR's apr_fnmatch function with flags=0, which is what
# Subversion uses.  Converts a string in fnmatch format to a Perl regexp.
# Code is based on Barrie Slaymaker's Regexp::Shellish.
sub compile_apr_fnmatch {
    my $re = shift;

    $re =~ s@
             (  \\.
             |  \[                       # character class
                   [!^]?                 # maybe negation (^ and ! are both supported)
                   (?: (?:\\.|[^\\\]])   # one item
                     (?: -               # possibly followed by a dash and another
                       (?:\\.|[^\\\]]))? # item
                   )*                    # 0 or more entries (zero case will be checked specially below)
                (\]?)                    # if this ] doesn't match, that means we fell off end of string!
             |  .
            )
             @
               if ( $1 eq '?' ) {
                   '.' ;
               } elsif ( $1 eq '*' ) {
                   '.*' ;
               } elsif ( substr($1, 0, 1) eq '[') {
                   if ($1 eq '[]') { # should never match
                       '[^\s\S]';
                   } elsif ($1 eq '[!]' or $1 eq '[^]') { # 0-length match
                       '';
                   } else {
                       my $temp = $1;
                       my $failed = $2 eq '';
                       if ($failed) {
                           '[^\s\S]';
                       } else {
                           $temp =~ s/(\\.|.)/$1 eq '-' ? '-' : quotemeta(substr($1, -1))/ges;
                           # the previous step puts in backslashes at beginning and end; remove them
                           $temp =~ s/^\\\[/[/;
                           $temp =~ s/\\\]$/]/;
                           # if it started with [^ or [!, it now starts with [\^ or [\!; fix.
                           $temp =~ s/^\[     # literal [
                                       \\     # literal backslash
                                       [!^]   # literal ! or ^
                                     /[^/x;
                           $temp;
                       }
                   }
               } else {
                   quotemeta(substr( $1, -1 ) ); # ie, either quote it, or if it's \x, quote x
               }
    @gexs ;

    return qr/\A$re\Z/s;
}

# Here be dragon. below is checkout_delta related function.

sub _delta_rev {
    my ($self, $arg) = @_;
    my $entry = $arg->{cinfo};
    my $schedule = $entry->{'.schedule'} || '';
    # XXX: uncomment this as mutation coverage test
    # return $cb_resolve_rev->($arg->{path}, $entry->{revision});

    # Lookup the copy source rev for the case of open_directory inside
    # add_directotry with history.  But shouldn't do so for replaced
    # items, because the rev here is used for delete_entry
    my ($source_path, $source_rev) = $schedule ne 'replace' ?
	$self->_copy_source($entry, $arg->{copath}) : ();
    ($source_path, $source_rev) = ($arg->{path}, $entry->{revision})
	unless defined $source_path;
    return $arg->{cb_resolve_rev}->($source_path, $source_rev);
}

sub _delta_content {
    my ($self, %arg) = @_;

    my $handle = $arg{editor}->apply_textdelta ($arg{baton}, $arg{md5}, $arg{pool});
    return unless $handle && $#{$handle} > 0;

    if ($arg{send_delta} && $arg{base}) {
	my $spool = SVN::Pool->new_default ($arg{pool});
	my $source = $arg{base_root}->file_contents ($arg{base_path}, $spool);
	my $txstream = SVN::TxDelta::new
	    ($source, $arg{fh}, $spool);
	SVN::TxDelta::send_txstream ($txstream, @$handle, $spool);
    }
    else {
	SVN::TxDelta::send_stream ($arg{fh}, @$handle, SVN::Pool->new ($arg{pool}))
    }
}

sub _unknown_verbose {
    my ($self, %arg) = @_;
    my $ignore = $self->ignore;
    # The caller should have processed the entry already.
    my %seen = ($arg{copath} => 1);
    my @new_targets;
    if ($arg{targets}) {
ENTRY:	for my $entry (@{$arg{targets}}) {
	    my $now = '';
	    for my $dir (splitdir ($entry)) {
		$now .= $now ? "/$dir" : $dir;
		my $copath = SVK::Path::Checkout->copath ($arg{copath}, $now);
		next if $seen{$copath};
		$seen{$copath} = 1;
		lstat $copath;
		unless (-e _) {
		    print loc ("Unknown target: %1.\n", $copath);
		    next ENTRY;
		}
		unless (-r _) {
		    print loc ("Warning: %1 is unreadable.\n", $copath);
		    next ENTRY;
		}
		$arg{cb_unknown}->($arg{editor}, catdir($arg{entry}, $now), $arg{baton});
	    }
	    push @new_targets, SVK::Path::Checkout->copath ($arg{copath}, $entry);
	}
	
	return unless @new_targets;
    }
    my $nentry = $arg{entry};
    to_native($nentry, 'path', $arg{encoder});
    find ({ preprocess => sub { sort @_ },
	    wanted =>
	    sub {
		$File::Find::prune = 1, return if m/$ignore/;
		my $copath = catdir($File::Find::dir, $_);
		return if $seen{$copath};
		my $schedule = $self->{checkout}->get ($copath)->{'.schedule'} || '';
		return if $schedule eq 'delete';
		my $dpath = abs2rel($copath, $arg{copath} => $nentry, '/');
		from_native($dpath, 'path');
		$arg{cb_unknown}->($arg{editor}, $dpath, $arg{baton});
	  }}, defined $arg{targets} ? @new_targets : $arg{copath});
}

sub _node_deleted {
    my ($self, %arg) = @_;
    $arg{rev} = $self->_delta_rev(\%arg);
    $arg{editor}->delete_entry (@arg{qw/entry rev baton pool/});

    if ($arg{kind} == $SVN::Node::dir && $arg{delete_verbose}) {
	foreach my $file (sort $self->{checkout}->find
			  ($arg{copath}, {'.schedule' => 'delete'})) {
	    next if $file eq $arg{copath};
	    $file = abs2rel($file, $arg{copath} => undef, '/');
	    from_native($file, 'path', $arg{encoder});
	    $arg{editor}->delete_entry ("$arg{entry}/$file", @arg{qw/rev baton pool/});
	}
    }
}

sub _node_deleted_or_absent {
    my ($self, %arg) = @_;
    my $schedule = $arg{cinfo}{'.schedule'} || '';

    if ($schedule eq 'delete' || $schedule eq 'replace') {
	my $should_do_delete = !$arg{_really_in_copy} || $arg{copath} eq ($arg{cinfo}{scheduleanchor} || '');
	$self->_node_deleted (%arg)
	    if $should_do_delete;
	# when doing add over deleted entry, descend into it
	if ($schedule eq 'delete') {
	    $self->_unknown_verbose (%arg)
		if $arg{cb_unknown} && $arg{unknown_verbose};
	    return $should_do_delete;
	}
    }

    if ($arg{type}) {
	if ($arg{kind} && !$schedule &&
	    (($arg{type} eq 'file') xor ($arg{kind} == $SVN::Node::file))) {
	    if ($arg{obstruct_as_replace}) {
		$self->_node_deleted (%arg);
	    }
	    else {
		$arg{cb_obstruct}->($arg{editor}, $arg{entry}, $arg{baton})
		    if $arg{cb_obstruct};
		return 1;
	    }
	}
    }
    else {
	# deleted during base_root -> xdroot
	if ($arg{xdroot} ne $arg{base_root} && $arg{kind} == $SVN::Node::none) {
	    $self->_node_deleted (%arg);
	    return 1;
	}
	return 1 if $arg{absent_ignore};
	# absent
	my $type = $arg{kind} == $SVN::Node::dir ? 'directory' : 'file';

	if ($arg{absent_as_delete}) {
	    $arg{rev} = $self->_delta_rev(\%arg);
	    $self->_node_deleted (%arg);
	}
	else {
	    my $func = "absent_$type";
	    $arg{editor}->$func (@arg{qw/entry baton pool/});
	}
	return 1 unless $type ne 'file' && $arg{absent_verbose};
    }
    return 0;
}

sub _prop_delta {
    my ($baseprop, $newprop) = @_;
    return $newprop unless $baseprop && keys %$baseprop;
    return { map {$_ => undef} keys %$baseprop } unless $newprop && keys %$newprop;
    my $changed;
    for my $propname (keys %{ { %$baseprop, %$newprop } }) {
	# deref propvalue
	my @value = map { $_ ? ref ($_) ? '' : $_ : '' }
	    map {$_->{$propname}} ($baseprop, $newprop);
	$changed->{$propname} = $newprop->{$propname}
	    unless $value[0] eq $value[1];
    }
    return $changed;
}

sub _prop_changed {
    my ($root1, $path1, $root2, $path2) = @_;
    ($root1, $root2) = map {$_->isa ('SVK::Root') ? $_->root : $_} ($root1, $root2);
    return SVN::Fs::props_changed ($root1, $path1, $root2, $path2);
}

sub _node_props {
    my ($self, %arg) = @_;
    my $schedule = $arg{cinfo}{'.schedule'} || '';
    my $props = $arg{kind} ? $schedule eq 'replace' ? {} : $arg{xdroot}->node_proplist ($arg{path}) :
	$arg{base_kind} ? $arg{base_root}->node_proplist ($arg{base_path}) : {};
    my $newprops = (!$schedule && $arg{auto_add} && $arg{kind} == $SVN::Node::none && $arg{type} eq 'file')
	? $self->auto_prop ($arg{copath}) : $arg{cinfo}{'.newprop'};
    my $fullprop = _combine_prop ($props, $newprops);
    if (!$arg{base} or $arg{in_copy}) {
	$newprops = $fullprop;
    }
    elsif ($arg{base_root} ne $arg{xdroot} && $arg{base}) {
	$newprops = _prop_delta ($arg{base_root}->node_proplist ($arg{base_path}), $fullprop)
	    if $arg{kind} && $arg{base_kind} && _prop_changed (@arg{qw/base_root base_path xdroot path/});
    }
    return ($newprops, $fullprop)
}

sub _node_type {
    my $copath = shift;
    my $st = [lstat ($copath)];
    return '' if !-e _;
    unless (-r _) {
	print loc ("Warning: $copath is unreadable.\n");
	return;
    }
    return ('file', $st) if -f _ or is_symlink;
    return ('directory', $st) if -d _;
    print loc ("Warning: unsupported node type $copath.\n");
    return ('', $st);
}

use Fcntl ':mode';

sub _delta_file {
    my ($self, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $cinfo = $arg{cinfo} ||= $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';
    my $modified;

    if ($arg{cb_conflict} && $cinfo->{'.conflict'}) {
	++$modified;
	$arg{cb_conflict}->($arg{editor}, $arg{entry}, $arg{baton});
    }

    return 1 if $self->_node_deleted_or_absent (%arg, pool => $pool);

    my ($newprops, $fullprops) = $self->_node_props (%arg);
    if (HAS_SYMLINK && (defined $fullprops->{'svn:special'} xor S_ISLNK($arg{st}[2]))) {
	# special case obstructure for links, since it's not standard
	return 1 if $self->_node_deleted_or_absent (%arg,
						    type => 'link',
						    pool => $pool);
	if ($arg{obstruct_as_replace}) {
	    $schedule = 'replace';
	    $fullprops = $newprops = $self->auto_prop($arg{copath}) || {};
	}
	else {
	    return 1;
	}
    }
    $arg{add} = 1 if $arg{auto_add} && $arg{base_kind} == $SVN::Node::none ||
	$schedule eq 'replace';

    my $fh = get_fh ($arg{xdroot}, '<', $arg{path}, $arg{copath}, $fullprops);
    my $mymd5 = md5_fh ($fh);
    my ($baton, $md5);

    $arg{base} = 0 if $arg{in_copy} || $schedule eq 'replace';

    unless ($schedule || $arg{add} ||
	($arg{base} && $mymd5 ne ($md5 = $arg{base_root}->file_md5_checksum ($arg{base_path})))) {
	$arg{cb_unchanged}->($arg{editor}, $arg{entry}, $arg{baton},
			     $self->_delta_rev(\%arg)
			    ) if ($arg{cb_unchanged} && !$modified);
	return $modified;
    }

    $baton = $arg{editor}->add_file ($arg{entry}, $arg{baton},
				     $cinfo->{'.copyfrom'} ?
				     ($arg{cb_copyfrom}->(@{$cinfo}{qw/.copyfrom .copyfrom_rev/}))
				     : (undef, -1), $pool)
	if $arg{add};

    $baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $self->_delta_rev(\%arg), $pool)
	if keys %$newprops;

    $arg{editor}->change_file_prop ($baton, $_, ref ($newprops->{$_}) ? undef : $newprops->{$_}, $pool)
	for sort keys %$newprops;

    if (!$arg{base} ||
	$mymd5 ne ($md5 ||= $arg{base_root}->file_md5_checksum ($arg{base_path}))) {
	seek $fh, 0, 0;
	$baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $self->_delta_rev(\%arg), $pool);
	$self->_delta_content (%arg, baton => $baton, pool => $pool,
			       fh => $fh, md5 => $arg{base} ? $md5 : undef);
    }

    $arg{editor}->close_file ($baton, $mymd5, $pool) if $baton;
    return 1;
}

sub _delta_dir {
    my ($self, %arg) = @_;
    # warn "===> $arg{entry} ".join(',',(caller)[0..2]) if $ENV{SVKDEBUG};
    if ($arg{entry} && $arg{exclude} && exists $arg{exclude}{$arg{entry}}) {
	$arg{cb_exclude}->($arg{path}, $arg{copath}) if $arg{cb_exclude};
	return;
    }
    my $pool = SVN::Pool->new_default (undef);
    my $cinfo = $arg{cinfo} ||= $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';
    $arg{add} = 1 if $arg{auto_add} && $arg{base_kind} == $SVN::Node::none ||
	$schedule eq 'replace';

    # compute targets for children
    my $targets;
    for (@{$arg{targets} || []}) {
	my ($volume, $directories, $file) = splitpath ($_);
	if ( my @dirs = splitdir($directories) ) {
	    my $path = $volume . shift(@dirs);
            $file = catdir(grep length, @dirs, $file);
	    push @{$targets->{$path}}, $file
	}
	else {
	    $targets->{$file} = undef;
	}
    }
    my $thisdir;
    if ($targets) {
	if (exists $targets->{''}) {
	    delete $targets->{''};
	    $thisdir = 1;
	}
    }
    else {
	$thisdir = 1;
    }
    # don't use depth when we are still traversing through targets
    my $descend = defined $targets || !(defined $arg{depth} && $arg{depth} == 0);
    $arg{cb_conflict}->($arg{editor}, $arg{entry}, $arg{baton})
	if $thisdir && $arg{cb_conflict} && $cinfo->{'.conflict'};

    return 1 if $self->_node_deleted_or_absent (%arg, pool => $pool);
    # if a node is replaced, it has no base, unless it was replaced with history.
    $arg{base} = 0 if $schedule eq 'replace' && !$cinfo->{'.copyfrom'};
    my ($entries, $baton) = ({});
    if ($arg{add}) {
	$baton = $arg{root} ? $arg{baton} :
	    $arg{editor}->add_directory ($arg{entry}, $arg{baton},
					 $cinfo->{'.copyfrom'} ?
					 ($arg{cb_copyfrom}->(@{$cinfo}{qw/.copyfrom .copyfrom_rev/}))
					 : (undef, -1), $pool);
    }

    $entries = $arg{base_root}->dir_entries ($arg{base_path})
	if $arg{base} && $arg{base_kind} == $SVN::Node::dir;

    $baton ||= $arg{root} ? $arg{baton}
	: $arg{editor}->open_directory ($arg{entry}, $arg{baton},
					$self->_delta_rev(\%arg), $pool);

    # check scheduled addition
    # XXX: does this work with copied directory?
    my ($newprops, $fullprops) = $self->_node_props (%arg);

    if ($descend) {

    my $signature;
    if ($self->{signature} && $arg{xdroot} eq $arg{base_root}) {
	$signature = $self->{signature}->load ($arg{copath});
	# if we are not iterating over all entries, keep the old signatures
	$signature->{keepold} = 1 if defined $targets
    }

    # XXX: Merge this with @direntries so we have single entry to descendents
    for my $entry (sort keys %$entries) {
	my $newtarget;
	my $copath = $entry;
	if (defined $targets) {
	    next unless exists $targets->{$copath};
	    $newtarget = delete $targets->{$copath};
	}
	to_native ($copath, 'path', $arg{encoder});
	my $kind = $entries->{$entry}->kind;
	my $unchanged = ($kind == $SVN::Node::file && $signature && !$signature->changed ($entry));
	$copath = SVK::Path::Checkout->copath ($arg{copath}, $copath);
	my ($ccinfo, $ccschedule) = $self->get_entry($copath);
	# a replace with history node requires handling the copy anchor in the
	# latter direntries loop.  we should really merge the two.
	if ($ccschedule eq 'replace' && $ccinfo->{'.copyfrom'}) {
	    delete $entries->{$entry};
	    $targets->{$entry} = $newtarget if defined $targets;
	    next;
	}
	my $newentry = defined $arg{entry} ? "$arg{entry}/$entry" : $entry;
	my $newpath = $arg{path} eq '/' ? "/$entry" : "$arg{path}/$entry";
	if ($unchanged && !$ccschedule && !$ccinfo->{'.conflict'}) {
	    $arg{cb_unchanged}->($arg{editor}, $newentry, $baton,
				 $self->_delta_rev({ %arg,
						     cinfo  => $ccinfo,
						     path   => $newpath,
						     copath => $copath })
				) if $arg{cb_unchanged};
	    next;
	}
	my ($type, $st) = _node_type ($copath);
	next unless defined $type;
	my $delta = $type ? $type eq 'directory' ? \&_delta_dir : \&_delta_file
	                  : $kind == $SVN::Node::file ? \&_delta_file : \&_delta_dir;
	my $obs = $type ? ($kind == $SVN::Node::dir xor $type eq 'directory') : 0;
	# if the sub-delta returns 1 it means the node is modified. invlidate
	# the signature cache
	$self->$delta ( %arg,
			add => $arg{in_copy} || ($obs && $arg{obstruct_as_replace}),
			type => $type,
			# if copath exist, we have base only if they are of the same type
			base => !$obs,
			depth => defined $arg{depth} ? defined $targets ? $arg{depth} : $arg{depth} - 1: undef,
			entry => $newentry,
			kind => $arg{xdroot} eq $arg{base_root} ? $kind : $arg{xdroot}->check_path ($newpath),
			base_kind => $kind,
			targets => $newtarget,
			baton => $baton,
			root => 0,
			st => $st,
			cinfo => $ccinfo,
			base_path => $arg{base_path} eq '/' ? "/$entry" : "$arg{base_path}/$entry",
			path => $newpath,
			copath => $copath)
	    and ($signature && $signature->invalidate ($entry));
    }

    if ($signature) {
	$signature->flush;
	undef $signature;
    }
    my $ignore = $self->ignore ($fullprops->{'svn:ignore'});

    my @direntries;
    # if we are at somewhere arg{copath} not exist, $arg{type} is empty
    if ($arg{type} && !(defined $targets && !keys %$targets)) {
	opendir my ($dir), $arg{copath} or Carp::confess "$arg{copath}: $!";
	for (readdir($dir)) {
	    # Completely deny the existance of .svk; we shouldn't
	    # show this even with e.g. --no-ignore.
	    next if $_ eq '.svk' and $self->{floating};

	    if (eval {from_native($_, 'path', $arg{encoder}); 1}) {
		push @direntries, $_;
	    }
	    elsif ($arg{auto_add}) { # fatal for auto_add
		die "$_: $@";
	    }
	    else {
		print "$_: $@";
	    }
	}
	@direntries = sort grep { !m/^\.+$/ && !exists $entries->{$_} } @direntries;
    }

    for my $copath (@direntries) {
	my $entry = $copath;
	my $newtarget;
	if (defined $targets) {
	    next unless exists $targets->{$copath};
	    $newtarget = delete $targets->{$copath};
	}
	to_native ($copath, 'path', $arg{encoder});
	my %newpaths = ( copath => SVK::Path::Checkout->copath ($arg{copath}, $copath),
			 entry => defined $arg{entry} ? "$arg{entry}/$entry" : $entry,
			 path => $arg{path} eq '/' ? "/$entry" : "$arg{path}/$entry",
			 base_path => $arg{base_path} eq '/' ? "/$entry" : "$arg{base_path}/$entry",
			 targets => $newtarget, base_kind => $SVN::Node::none);
	$newpaths{kind} = $arg{xdroot} eq $arg{base_root} ? $SVN::Node::none :
	    $arg{xdroot}->check_path ($newpaths{path}) != $SVN::Node::none;
	my ($ccinfo, $sche) = $self->get_entry($newpaths{copath});
	my $add = $sche || $arg{auto_add} || $newpaths{kind};
	# If we are not at intermediate path, process ignore
	# for unknowns, as well as the case of auto_add (import)
	if (!defined $targets) {
	    if ((!$add || $arg{auto_add}) && $entry =~ m/$ignore/) { 
		$arg{cb_ignored}->($arg{editor}, $newpaths{entry}, $arg{baton})
		    if $arg{cb_ignored};
		next;
	    }
	}
	if ($ccinfo->{'.conflict'}) {
	    $arg{cb_conflict}->($arg{editor}, $newpaths{entry}, $arg{baton})
		if $arg{cb_conflict};
	}
	unless ($add || $ccinfo->{'.conflict'}) {
	    if ($arg{cb_unknown}) {
		$arg{cb_unknown}->($arg{editor}, $newpaths{entry}, $arg{baton});
		$self->_unknown_verbose (%arg, %newpaths)
		    if $arg{unknown_verbose};
	    }
	    next;
	}
	my ($type, $st) = _node_type ($newpaths{copath}) or next;
	my $delta = $type eq 'directory' ? \&_delta_dir : \&_delta_file;
	my $copyfrom = $ccinfo->{'.copyfrom'};
	my $fromroot = $copyfrom ? $arg{repos}->fs->revision_root ($ccinfo->{'.copyfrom_rev'}) : undef;
	$self->$delta ( %arg, %newpaths, add => 1, baton => $baton,
			root => 0, base => 0, cinfo => $ccinfo,
			type => $type,
			st => $st,
			depth => defined $arg{depth} ? defined $targets ? $arg{depth} : $arg{depth} - 1: undef,
			$copyfrom ?
			( base => 1,
			  _really_in_copy => 1,
			  in_copy => $arg{expand_copy},
			  base_kind => $fromroot->check_path ($copyfrom),
			  base_root => $fromroot,
			  base_path => $copyfrom) : (),
		      );
    }

    }

    if ($thisdir) {
	$arg{editor}->change_dir_prop ($baton, $_, ref ($newprops->{$_}) ? undef : $newprops->{$_}, $pool)
	    for sort keys %$newprops;
    }
    if (defined $targets) {
	print loc ("Unknown target: %1.\n", $_) for sort keys %$targets;
    }

    $arg{editor}->close_directory ($baton, $pool)
	unless $arg{root};
    return 0;
}

sub _get_rev {
    $_[0]->{checkout}->get ($_[1])->{revision};
}

sub checkout_delta {
    my ($self, %arg) = @_;
    $arg{base_root} ||= $arg{xdroot}; # xdroot is the  
    $arg{base_path} ||= $arg{path};   # path is  ->  string name of file in repo
    $arg{encoder} = get_encoder;
    Carp::cluck unless defined $arg{base_path};
    my $kind = $arg{base_kind} = $arg{base_root}->check_path ($arg{base_path});
    $arg{kind} = $arg{base_root} eq $arg{xdroot} ? $kind : $arg{xdroot}->check_path ($arg{path});
    die "checkout_delta called with non-dir node"
	   unless $kind == $SVN::Node::dir;
    my ($copath, $repospath) = @arg{qw/copath repospath/};
    $arg{editor} = SVN::Delta::Editor->new (_debug => 1, _editor => [$arg{editor}])
	if $arg{debug};
    $arg{editor} = SVK::Editor::Delay->new ($arg{editor})
	   unless $arg{nodelay};

    my $cb_resolve_rev = $arg{cb_resolve_rev} ||= sub { $_[1] };
    # XXX: translate $repospath to use '/'
    $arg{cb_copyfrom} ||= $arg{expand_copy} ? sub { (undef, -1) }
	: sub { ("file://$repospath$_[0]", $_[1]) };
    my ($entry) = $self->get_entry($arg{copath});
    my $rev = $arg{cb_resolve_rev}->($arg{path}, $entry->{revision});
    local $SIG{INT} = sub {
	$arg{editor}->abort_edit;
	die loc("Interrupted.\n");
    };

    my $baton = $arg{editor}->open_root ($rev);
    $self->_delta_dir (%arg, baton => $baton, root => 1, base => 1, type => 'directory');
    $arg{editor}->close_directory ($baton);
    $arg{editor}->close_edit ();
}

=item get_entry($copath)

Returns the L<Data::Hierarchy> entry and the schedule of the entry.

=cut

sub get_entry {
    my ($self, $copath) = @_;
    my $entry = $self->{checkout}->get($copath);
    return ($entry, $entry->{'.schedule'} || '');
}

sub resolved_entry {
    my ($self, $entry) = @_;
    my $val = $self->{checkout}->get ($entry);
    return unless $val && $val->{'.conflict'};
    $self->{checkout}->store ($entry, {%$val, '.conflict' => undef});
    print loc("%1 marked as resolved.\n", $entry);
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
    $entry = $self->{checkout}->get ($entry->{scheduleanchor})
	if $entry->{scheduleanchor} ne $copath;
    my $from = $entry->{'.copyfrom'} or return;
    $from .= $descendent;
    return ($from, $root ? $root->fs->revision_root ($entry->{'.copyfrom_rev'})
	    : $entry->{'.copyfrom_rev'});
}

sub get_props {
    my ($self, $root, $path, $copath, $entry) = @_;
    my $props = {};
    $entry ||= $self->{checkout}->get ($copath) if $copath;
    my $schedule = $entry->{'.schedule'} || '';

    if (my ($source_path, $source_root) = $self->_copy_source ($entry, $copath, $root)) {
	$props = $source_root->node_proplist ($source_path);
    }
    elsif ($schedule ne 'add' && $schedule ne 'replace') {
	Carp::cluck 'hate' unless defined $path;
	$props = $root->node_proplist ($path);
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

sub _mirror {
    my ($self, $repos) = @_;
    return SVK::Mirror->new
	( { repos => $repos,
	    config => $self->{svnconfig},
	    revprop => ['svk:signature'] });
}

sub mirror {
    my ($self, $repos) = @_;
    return $repos ? $self->_mirror($repos) :
	map { $self->_mirror($_) } values %{$self->{depotmap}};
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

package SVK::XD::Root;
require SVK::Root;

sub new {
    my ($class, @arg) = @_;
    unshift @arg, undef if $#arg == 0;
    return SVK::Root->new({ txn => $arg[0], root => $arg[1]});
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
