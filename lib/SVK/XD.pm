package SVK::XD;
use strict;
our $VERSION = $SVK::VERSION;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
require SVN::Delta;
require SVK::Merge;
use SVK::Editor::Status;
use SVK::Editor::Delay;
use SVK::Editor::XD;
use SVK::I18N;
use SVK::Util qw( get_anchor abs_path abs2rel splitdir catdir splitpath $SEP
		  HAS_SYMLINK is_symlink is_executable mimetype mimetype_is_text
		  md5_fh  traverse_history );
use Data::Hierarchy 0.18;
use File::Spec;
use File::Find;
use File::Path;
use YAML qw(LoadFile DumpFile);
use PerlIO::eol 0.10 qw( NATIVE LF );
use PerlIO::via::dynamic;
use PerlIO::via::symlink;
use Regexp::Shellish qw( compile_shellish ) ;

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
    $self->{signature} ||= SVK::XD::Signature->new (root => $self->cache_directory)
	if $self->{svkpath};
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

    mkdir($self->{svkpath}) or die loc("Cannot create svk-config-directory at '%1': %2", $self->{svkpath}, $!)
        unless -d $self->{svkpath};

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
        }
    }

    $info ||= { depotmap => {'' => catdir($self->{svkpath}, 'local') },
	        checkout => Data::Hierarchy->new( sep => $SEP ) };
    $self->{$_} = $info->{$_} for keys %$info;
}

=item store

Serialize C<$self> to the statefile. If giant lock is still ours,
overwrite the file directly. Otherwise load the file again and merge
the paths we locked into the new state file. After C<store> is called,
giant is unlocked.

=cut

sub _store_self {
    my ($self, $hash) = @_;
    DumpFile ($self->{statefile},
	      { map { $_ => $hash->{$_}} qw/checkout depotmap/ });
}

sub store {
    my ($self) = @_;
    $self->{updated} = 1;
    return unless $self->{statefile};
    local $@;
    if ($self->{giantlocked}) {
	$self->_store_self ($self, $self);
    }
    elsif ($self->{modified}) {
	$self->giant_lock ();
	my $info = LoadFile ($self->{statefile});
	my @paths = $info->{checkout}->find ('/', {lock => $$});
	$info->{checkout}->merge ($self->{checkout}, $_)
	    for @paths;
	$self->_store_self ($self, $info);
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
    DumpFile ($self->{statefile}, { checkout => $self->{checkout},
				    depotmap => $self->{depotmap}} )
	if $self->{statefile};

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
        die loc("another svk might be running; remove %1 if not", $self->{giantlock});
    }

    open my ($lock), '>', $self->{giantlock}
	or die loc("cannot acquire giant lock");
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

sub _reset_repos {
    %REPOS = ();
    $REPOSPOOL = SVN::Pool->new;
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

    my $repospath = $self->{depotmap}{$depot} or die loc("no such depot: %1", $depot);

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

=item condense

=back

=cut

sub condense {
    my $self = shift;
    my @targets = map {abs_path($_)} @_;
    my ($anchor, $report);
    for my $path (@_) {
	my $copath = abs_path ($path);
	die loc("path %1 is not a checkout path.\n", $path)
	    unless $copath;
	if (!$anchor) {
	    $anchor = $copath;
	    $report = $_[0];
	}
	my $cinfo = $self->{checkout}->get ($anchor);
	my $schedule = $cinfo->{'.schedule'} || '';
	while (!-d $anchor || $cinfo->{scheduleanchor} ||
	       $schedule eq 'add' || $schedule eq 'delete' || $schedule eq 'replace' ||
	       ($anchor ne $copath && $anchor.$SEP ne substr ($copath, 0, length($anchor)+1))) {
	    ($anchor, $report) = get_anchor (0, $anchor, $report);
	    # XXX: put .. to report if it's anchorified beyond
	    $cinfo = $self->{checkout}->get ($anchor);
	    $schedule = $cinfo->{'.schedule'} || '';
	}
    }
    return ($report, $anchor, map { abs2rel($_, $anchor) } grep {$_ ne $anchor} @targets);
}

sub xdroot {
    SVK::XD::Root->new (create_xd_root (@_));
}

sub create_xd_root {
    my ($self, %arg) = @_;
    my ($fs, $copath) = ($arg{repos}->fs, $arg{copath});
    my ($txn, $root);

    my @paths = $self->{checkout}->find ($copath, {revision => qr'.*'});

    return (undef, $fs->revision_root
	    ($self->{checkout}->get ($paths[0] || $copath)->{revision}))
	if $#paths <= 0;

    for (@paths) {
	my $cinfo = $self->{checkout}->get ($_);
	unless ($root) {
	    $txn = $fs->begin_txn ($cinfo->{revision});
	    $root = $txn->root();
	    next if $_ eq $copath;
	}
	my $path = abs2rel($_, $copath => $arg{path}, '/');
	$root->delete ($path)
	    if eval { $root->check_path ($path) != $SVN::Node::none };
	SVN::Fs::revision_link ($fs->revision_root ($cinfo->{revision}),
				$root, $path)
		unless $cinfo->{'.deleted'};
    }
    return ($txn, $root);
}

=head2 Checkout handling

=over

=cut

sub xd_storage_cb {
    my ($self, %arg) = @_;
    # translate to abs path before any check
    return
	( cb_exist => sub { $_ = shift; $arg{get_copath} ($_); -e $_ || is_symlink($_) },
	  cb_rev => sub { $_ = shift; $arg{get_copath} ($_);
			  $self->{checkout}->get ($_)->{revision} },
	  cb_conflict => sub { $_ = shift; $arg{get_copath} ($_);
			       $self->{checkout}->store ($_, {'.conflict' => 1})
				   unless $arg{check_only};
			   },
	  cb_localmod => sub { my ($path, $checksum) = @_;
			       my $copath = $path;
			       # XXX: make use of the signature here too
			       $arg{get_copath} ($copath);
			       $arg{get_path} ($path);
			       my $base = get_fh ($arg{oldroot}, '<',
						  $path, $copath);
			       my $md5 = md5_fh ($base);
			       return undef if $md5 eq $checksum;
			       seek $base, 0, 0;
			       return [$base, undef, $md5];
			   },
	  cb_dirdelta => sub { my ($path, $base_root, $base_path, $pool) = @_;
			       my $copath = $path;
			       $arg{get_copath} ($copath);
			       $arg{get_path} ($path);
			       my $modified;
			       my $editor =  SVK::Editor::Status->new
				   ( notify => SVK::Notify->new
				     ( cb_flush => sub {
					   my ($path, $status) = @_;
					   $modified->{$path} = $status->[0];
				       }));
			       $self->checkout_delta
				   ( %arg,
				     # XXX: proper anchor handling
				     path => $path,
				     copath => $copath,
				     base_root => $base_root,
				     base_path => $base_path,
				     xdroot => $arg{oldroot},
				     nodelay => 1,
				     depth => 1,
				     editor => $editor,
				     absent_as_delete => 1,
				     cb_unknown =>
				     sub {
					 my $unknown = abs2rel($_[0], $path);
					 $modified->{$unknown} = '?';
				     },
				   );
			       return $modified;
			   },
	);
}

=item get_editor

Returns the L<SVK::XD::Editor> object. Apply target translation if
target is given in options. Also returns the callback hash used by
L<SVK::Editor::Merge> when called in array context.

=cut

sub get_editor {
    my ($self, %arg) = @_;
    my ($copath, $path) = @arg{qw/copath path/};
    $path = '' if $path eq '/';
    $arg{get_copath} = sub { $_[0] = SVK::Target->copath ($copath,  $_[0]) };
    $arg{get_path} = sub { $_[0] = "$path/$_[0]" };
    my $storage = SVK::Editor::XD->new (%arg, xd => $self);

    return wantarray ? ($storage, $self->xd_storage_cb (%arg)) : $storage;
}

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
		       sub { $self->{svnautoprop}{compile_shellish $_[0]} = $_[1]; 1} );
    };
    warn "Your svn is too old, auto-prop in svn config is not supported: $@\n" if $@;
}

sub auto_prop {
    my ($self, $copath) = @_;

    # no other prop for links
    return {'svn:special' => '*'} if is_symlink($copath);
    my $prop;
    $prop->{'svn:executable'} = '*' if is_executable($copath);
    # auto mime-type
    open my $fh, '<', $copath or die "$copath: $!";
    if (my $type = mimetype($fh)) {
	# add only binary mime types or text/* but not text/plain
	$prop->{'svn:mime-type'} = $type
	    if $type ne 'text/plain' &&
		($type =~ m/^text/ || !mimetype_is_text ($type));
    }
    # svn auto-prop
    if ($self->{svnconfig} && $self->{svnconfig}{config}->get_bool ('miscellany', 'enable-auto-props', 0)) {
	$self->_load_svn_autoprop unless $self->{svnautoprop};
	my (undef, undef, $filename) = splitpath ($copath);
	while (my ($pattern, $value) = each %{$self->{svnautoprop}}) {
	    next unless $filename =~ m/$pattern/;
	    for (split (';', $value)) {
		my ($propname, $propvalue) = split ('=', $_, 2);
		$prop->{$propname} = $propvalue;
	    }
	}
    }
    return $prop;
}

sub do_delete {
    my ($self, %arg) = @_;
    my $xdroot = $self->xdroot (%arg);
    my @deleted;

    # check for if the file/dir is modified.
    unless ($arg{targets}) {
	my $target;
	($arg{path}, $target, $arg{copath}, undef, $arg{report}) =
	    get_anchor (1, @arg{qw/path copath report/});
	$arg{targets} = [$target];
    }

    $self->checkout_delta ( %arg,
			    xdroot => $xdroot,
			    absent_as_delete => 1,
			    delete_verbose => 1,
			    absent_verbose => 1,
			    editor => SVK::Editor::Status->new
			    ( notify => SVK::Notify->new
			      ( cb_flush => sub {
				    my ($path, $status) = @_;
				    my ($copath, $report) = map { SVK::Target->copath ($_, $path) }
					@arg{qw/copath report/};
				    my $st = $status->[0];
				    if ($st eq 'M') {
					die loc("%1 changed", $report);
				    }
				    elsif ($st eq 'D') {
					push @deleted, $copath;
				    }
				    elsif (-f $copath) {
					die loc("%1 is scheduled, use 'svk revert'", $report);
				    }
				})),
			    cb_unknown => sub {
				die loc("%1 is not under version control", $_[0]);
			    }
			  );

    # actually remove it from checkout path
    my @paths = grep {is_symlink($_) || -e $_} (exists $arg{targets}[0] ?
			      map { SVK::Target->copath ($arg{copath}, $_) } @{$arg{targets}}
			      : $arg{copath});
    my $ignore = ignore ();
    find(sub {
	     return if m/$ignore/;
	     my $cpath = catdir($File::Find::dir, $_);
	     no warnings 'uninitialized';
	     return if $self->{checkout}->get ($cpath)->{'.schedule'}
		 eq 'delete';
	     push @deleted, $cpath;
	 }, @paths) if @paths;

    for (@deleted) {
	my $rpath = abs2rel($_, $arg{copath} => $arg{report});
	print "D   $rpath\n" unless $arg{quiet};
	$self->{checkout}->store ($_, {'.schedule' => 'delete'});
    }

    return if $arg{no_rm};
    rmtree (\@paths) if @paths;
}

sub do_proplist {
    my ($self, $target) = @_;

    return $self->get_props ($target->root ($self), $target->{path}, $target->{copath});
}

sub do_propset {
    my ($self, %arg) = @_;
    my ($xdroot, %values);
    my $entry = $self->{checkout}->get ($arg{copath});
    $entry->{'.schedule'} ||= '';
    $entry->{'.newprop'} ||= {};

    unless ($entry->{'.schedule'} eq 'add' || !$arg{repos}) {
	$xdroot = $self->xdroot (%arg);
	my ($source_path, $source_root) = $self->_copy_source ($entry, $arg{copath}, $xdroot);
	$source_path ||= $arg{path}; $source_root ||= $xdroot;
	die loc("%1(%2) is not under version control", $arg{copath}, $source_path)
	    if $xdroot->check_path ($source_path) == $SVN::Node::none;
    }

    #XXX: support working on multiple paths and recursive
    die loc("%1 is already scheduled for delete", $arg{copath})
	if $entry->{'.schedule'} eq 'delete';
    %values = %{$entry->{'.newprop'}}
	if exists $entry->{'.schedule'};
    my $pvalue = defined $arg{propvalue} ? $arg{propvalue} : \undef;

    $self->{checkout}->store ($arg{copath},
			      { '.schedule' => $entry->{'.schedule'} || 'prop',
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
    my @root = map {$_->isa ('SVK::XD::Root') ? $_->[1] : $_} @arg{qw/oldroot newroot/};
    # XXX: if dir_delta croaks the editor would leak since the baton is not properly destroyed.
    SVN::Repos::dir_delta ($root[0], @{$arg{oldpath}},
			   $root[1], $arg{newpath},
			   $arg{editor}, undef,
			   $arg{no_textdelta} ? 0 : 1,
			   $arg{no_recurse} ? 0 : 1,
			   0, # we never need entry props
			   $arg{notice_ancestry} ? 0 : 1);
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

=back

=cut

# XXX: checkout_delta is getting too complicated and too many options
my %ignore_cache;

sub ignore {
    no warnings;
    my @ignore = qw/*.o #*# .#* *.lo *.la .*.rej *.rej .*~ *~ .DS_Store
		    svk-commit*.tmp/;

    return join('|', map {$ignore_cache{$_} ||= compile_shellish $_} (@ignore, @_));
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
    my $ignore = ignore;
    my %seen;
    if ($arg{targets}) {
	$arg{cb_unknown}->($arg{entry}, $arg{copath});
	for my $entry (@{$arg{targets}}) {
	    my $now = '';
	    for my $dir (splitdir ($entry)) {
		$now .= $now ? "/$dir" : $dir;
		my $copath = SVK::Target->copath ($arg{copath}, $now);
		next if $seen{$copath};
		$arg{cb_unknown}->(catdir($arg{entry}, $now), $copath);
		$seen{$copath} = 1;
	    }
	}
    }
    find ({ preprocess => sub { sort @_ },
	    wanted =>
	    sub {
		$File::Find::prune = 1, return if m/$ignore/;
		my $dpath = catdir($File::Find::dir, $_);
		my $copath = $dpath;
		return if $seen{$copath};
		my $schedule = $self->{checkout}->get ($copath)->{'.schedule'} || '';
		return if $schedule eq 'delete';
		$dpath = abs2rel($dpath, $arg{copath} => $arg{entry}, '/');
		$arg{cb_unknown}->($dpath, $copath);
	  }}, defined $arg{targets} ?
	  map { SVK::Target->copath ($arg{copath}, $_) } @{$arg{targets}} : $arg{copath});
}

sub _node_deleted {
    my ($self, %arg) = @_;
    $arg{rev} = $arg{cb_rev}->($arg{entry});
    $arg{editor}->delete_entry (@arg{qw/entry rev baton pool/});

    if ($arg{kind} == $SVN::Node::dir && $arg{delete_verbose}) {
	foreach my $file (sort $self->{checkout}->find
			  ($arg{copath}, {'.schedule' => 'delete'})) {
	    $file = abs2rel($file, $arg{copath} => undef, '/');
	    $arg{editor}->delete_entry ("$arg{entry}/$file", @arg{qw/rev baton pool/})
		if $file;
	}
    }
}

sub _node_deleted_or_absent {
    my ($self, %arg) = @_;
    my $schedule = $arg{cinfo}{'.schedule'} || '';

    if ($schedule eq 'delete' || $schedule eq 'replace') {
	$self->_node_deleted (%arg);
	if ($schedule eq 'delete') {
	    $self->_unknown_verbose (%arg)
		if $arg{cb_unknown} && $arg{unknown_verbose};
	    return 1;
	}
    }

    if ($arg{type}) {
	if ($arg{kind} && (($arg{type} eq 'file') xor ($arg{kind} == $SVN::Node::file))) {
	    if ($arg{obstruct_as_replace}) {
		$self->_node_deleted (%arg);
	    }
	    else {
		$arg{cb_obstruct}->($arg{editor}, $arg{entry}, $arg{baton})
		    if $arg{cb_obstruct};
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
	    $arg{rev} = $arg{cb_rev}->($arg{entry});
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
    ($root1, $root2) = map {$_->isa ('SVK::XD::Root') ? $_->[1] : $_} ($root1, $root2);
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
    if ($arg{add}) {
	$newprops = $fullprop;
    }
    elsif ($arg{base_root} ne $arg{xdroot} && $arg{base}) {
	$newprops = _prop_delta ($arg{base_root}->node_proplist ($arg{base_path}), $fullprop)
	    if $arg{kind} && $arg{base_kind} && _prop_changed (@arg{qw/base_root base_path xdroot path/});
    }
    return ($newprops, $fullprop)
}

sub _delta_file {
    my ($self, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $cinfo = $arg{cinfo} ||= $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';
    my $modified;
    $arg{add} = 1 if $arg{auto_add} && $arg{base_kind} == $SVN::Node::none ||
	$schedule eq 'replace';

    if ($arg{cb_conflict} && $cinfo->{'.conflict'}) {
	++$modified;
	$arg{cb_conflict}->($arg{editor}, $arg{entry}, $arg{baton});
    }

    return 1 if $self->_node_deleted_or_absent (%arg, pool => $pool);

    my ($newprops, $fullprops) = $self->_node_props (%arg);
    my $fh = get_fh ($arg{xdroot}, '<', $arg{path}, $arg{copath}, $fullprops);
    my $mymd5 = md5_fh ($fh);
    my ($baton, $md5);

    $arg{base} = 0 if $arg{in_copy} || $schedule eq 'replace';;

    return $modified unless $schedule || $arg{add} ||
	($arg{base} && $mymd5 ne ($md5 = $arg{base_root}->file_md5_checksum ($arg{base_path})));

    $baton = $arg{editor}->add_file ($arg{entry}, $arg{baton},
				     $cinfo->{'.copyfrom'} ?
				     ($arg{cb_copyfrom}->(@{$cinfo}{qw/.copyfrom .copyfrom_rev/}))
				     : (undef, -1), $pool)
	if $arg{add};

    $baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $arg{cb_rev}->($arg{entry}), $pool)
	if keys %$newprops;

    $arg{editor}->change_file_prop ($baton, $_, ref ($newprops->{$_}) ? undef : $newprops->{$_}, $pool)
	for sort keys %$newprops;

    if (!$arg{base} ||
	$mymd5 ne ($md5 ||= $arg{base_root}->file_md5_checksum ($arg{base_path}))) {
	seek $fh, 0, 0;
	$baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $arg{cb_rev}->($arg{entry}), $pool);
	$self->_delta_content (%arg, baton => $baton, pool => $pool,
			       fh => $fh, md5 => $arg{base} ? $md5 : undef);
    }

    $arg{editor}->close_file ($baton, $mymd5, $pool) if $baton;
    return 1;
}

sub _delta_dir {
    my ($self, %arg) = @_;
    return if defined $arg{depth} && $arg{depth} == 0;
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
    $arg{cb_conflict}->($arg{editor}, $arg{entry}, $arg{baton})
	if $arg{cb_conflict} && $cinfo->{'.conflict'};

    return if $self->_node_deleted_or_absent (%arg, pool => $pool);
    $arg{base} = 0 if $schedule eq 'replace';
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
					$arg{cb_rev}->($arg{entry}), $pool);

    my $signature;
    if ($self->{signature} && $arg{xdroot} eq $arg{base_root}) {
	$signature = $self->{signature}->load ($arg{copath});
	# if we are not iterating over all entries, keep the old signatures
	$signature->{keepold} = 1 if defined $targets
    }

    # XXX: Merge this with @direntries so we have single entry to descendents
    for my $entry (sort keys %$entries) {
	my $newtarget;
	if (defined $targets) {
	    next unless exists $targets->{$entry};
	    $newtarget = delete $targets->{$entry};
	}
	my $kind = $entries->{$entry}->kind;
	my $unchanged = ($kind == $SVN::Node::file && $signature && !$signature->changed ($entry));
	my $copath = SVK::Target->copath ($arg{copath}, $entry);
	my $ccinfo = $self->{checkout}->get ($copath);
	next if $unchanged && !$ccinfo->{'.schedule'} && !$ccinfo->{'.conflict'};
	# XXX: save this stat() result for node_delete_or_absent
	lstat ($copath);
	my $type = -e _ ? (-d _ and not is_symlink) ? 'directory' : 'file'
	                : '';
	my $delta = $type ? $type eq 'directory' ? \&_delta_dir : \&_delta_file
	                  : $kind == $SVN::Node::file ? \&_delta_file : \&_delta_dir;
	my $newpath = $arg{path} eq '/' ? "/$entry" : "$arg{path}/$entry";
	my $obs = $type ? ($kind == $SVN::Node::dir xor $type eq 'directory') : 0;
	$self->$delta ( %arg,
			add => $arg{in_copy} || ($obs && $arg{obstruct_as_replace}),
			type => $type,
			# if copath exist, we have base only if they are of the same type
			base => !$obs,
			depth => $arg{depth} ? $arg{depth} - 1: undef,
			entry => defined $arg{entry} ? "$arg{entry}/$entry" : $entry,
			kind => $arg{xdroot} eq $arg{base_root} ? $kind : $arg{xdroot}->check_path ($newpath),
			base_kind => $kind,
			targets => $newtarget,
			baton => $baton,
			root => 0,
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

    # check scheduled addition
    # XXX: does this work with copied directory?
    my ($newprops, $fullprops) = $self->_node_props (%arg);
    my $ignore = ignore (split ("\n", $fullprops->{'svn:ignore'} || ''));

    my @direntries;
    unless (defined $targets && !keys %$targets) {
	opendir my ($dir), $arg{copath} or die "$arg{copath}: $!";
	@direntries = sort grep { !m/^\.+$/ && !exists $entries->{$_} } readdir ($dir);
    }

    for my $entry (@direntries) {
	my $newtarget;
	if (defined $targets) {
	    next unless exists $targets->{$entry};
	    $newtarget = delete $targets->{$entry};
	}
	my %newpaths = ( copath => SVK::Target->copath ($arg{copath}, $entry),
			 entry => defined $arg{entry} ? "$arg{entry}/$entry" : $entry,
			 path => $arg{path} eq '/' ? "/$entry" : "$arg{path}/$entry",
			 base_path => $arg{base_path} eq '/' ? "/$entry" : "$arg{base_path}/$entry",
			 targets => $newtarget, base_kind => $SVN::Node::none);
	$newpaths{kind} = $arg{xdroot} eq $arg{base_root} ? $SVN::Node::none :
	    $arg{xdroot}->check_path ($newpaths{path}) != $SVN::Node::none;
	my $ccinfo = $self->{checkout}->get ($newpaths{copath});
	my $sche = $ccinfo->{'.schedule'} || '';
	my $add = $sche || $arg{auto_add} || $newpaths{kind};
	unless ($add) {
	    next if !defined $targets && $entry =~ m/$ignore/ ;
	    if ($arg{cb_unknown}) {
		if ($arg{unknown_verbose}) {
		    $self->_unknown_verbose (%arg, %newpaths);
		}
		else {
		    $arg{cb_unknown}->($newpaths{entry}, $newpaths{copath});
		}
	    }
	    next;
	}
	lstat ($newpaths{copath});
	# XXX: warn about unreadable entry?
	next unless -r _;
	my $type = (-d _ and not is_symlink) ? 'directory' : 'file';
	my $delta = $type eq 'directory' ? \&_delta_dir : \&_delta_file;
	my $copyfrom = $ccinfo->{'.copyfrom'};
	my $fromroot = $copyfrom ? $arg{repos}->fs->revision_root ($ccinfo->{'.copyfrom_rev'}) : undef;
	$self->$delta ( %arg, %newpaths, add => 1, baton => $baton,
			root => 0, base => 0, cinfo => $ccinfo,
			type => $type,
			$copyfrom ?
			( base => 1,
			  in_copy => $arg{expand_copy},
			  base_kind => $fromroot->check_path ($copyfrom),
			  base_root => $fromroot,
			  base_path => $copyfrom) : (),
		      );
    }

    unless (defined $targets) {
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
    $arg{base_root} ||= $arg{xdroot};
    $arg{base_path} ||= $arg{path};
    my $kind = $arg{base_kind} = $arg{base_root}->check_path ($arg{base_path});
    $arg{kind} = $arg{base_root} eq $arg{xdroot} ? $kind : $arg{xdroot}->check_path ($arg{path});
    die "checkout_delta called with non-dir node"
	unless $kind == $SVN::Node::dir;
    my ($copath, $repospath) = @arg{qw/copath repospath/};
    $arg{editor} = SVK::Editor::Delay->new ($arg{editor})
	unless $arg{nodelay};
    $arg{editor} = SVN::Delta::Editor->new (_debug => 1, _editor => [$arg{editor}])
	if $arg{debug};
    $arg{cb_rev} ||= sub { $self->_get_rev (SVK::Target->copath ($copath, $_[0])) };
    # XXX: translate $repospath to use '/'
    $arg{cb_copyfrom} ||= $arg{expand_copy} ? sub { (undef, -1) }
	: sub { ("file://$repospath$_[0]", $_[1]) };
    my $rev = $arg{cb_rev}->('');
    local $SIG{INT} = sub {
	$arg{editor}->abort_edit;
	die loc("Interrupted.\n");
    };

    my $baton = $arg{editor}->open_root ($rev);
    $self->_delta_dir (%arg, baton => $baton, root => 1, base => 1, type => 'directory');
    $arg{editor}->close_directory ($baton);
    $arg{editor}->close_edit ();
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
    my ($root, $path, $prop, $mode) = @_;
    my $k = $prop->{'svn:eol-style'} or return ':raw';
    # short-circuit no-op write layers on lf platforms
    if (NATIVE eq LF) {
	return ':raw' if $mode eq '>' && ($k eq 'native' or $k eq 'LF');
    }
    if ($k eq 'native') {
        return ':raw:eol(LF!-Native!)';
    }
    elsif ($k eq 'CRLF' or $k eq 'CR' or $k eq 'LF') {
        return ":raw:eol($k!)";
    }
    else {
        return ':raw'; # unsupported
    }
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
         sub { $_[1] =~ s/\$($keyword)\b[-#:\w\t \.\/]*\$/"\$$1: ".$kmap{$1}->($root, $path).' $'/eg; },
	 untranslate =>
	 sub { $_[1] =~ s/\$($keyword)\b[-#:\w\t \.\/]*\$/\$$1\$/g; });
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
	local $@;
	$prop ||= eval { $root->node_proplist ($path) };
    }
    return _fh_symlink ($mode, $fname)
	if HAS_SYMLINK and ( defined $prop->{'svn:special'} || ($mode eq '<' && is_symlink($fname)) );
    if (keys %$prop) {
	$layer ||= get_keyword_layer ($root, $path, $prop);
	$eol ||= get_eol_layer($root, $path, $prop, $mode);
    }
    $eol ||= ':raw';
    open my ($fh), $mode.$eol, $fname or die "can't open $fname: $!\n";
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
	die loc("path %1 not found", $path)
	    if $root->check_path ($path) == $SVN::Node::none;
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
    $spath =~ s{(?=[_=])}{=}g;
    $spath =~ s{:}{=-}g;
    $spath =~ s{\Q$SEP}{_}go;
    my $self = bless { root => $factory->{root},
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
    return $self->path.'_lock';
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
use SVK::I18N;

sub AUTOLOAD {
    my $func = our $AUTOLOAD;
    $func =~ s/^SVK::XD::Root:://;
    return if $func =~ m/^[A-Z]*$/;

    no strict 'refs';
    no warnings 'redefine';

    *$func = sub {
        my $self = shift;
        # warn "===> $self $func: ".join(',',@_).' '.join(',', (caller(0))[0..3])."\n";
        $self->[1]->$func (@_);
    };

    goto &$func;
}

sub new {
    my ($class, @arg) = @_;
    unshift @arg, undef if $#arg == 0;
    bless [@arg], $class;
}

# XXX: workaround some stalled refs in svn/perl
my $globaldestroy;

sub DESTROY {
    warn "===> attempt to destroy root $_[0], leaked?" if $globaldestroy;
    return if $globaldestroy;
    $_[0][0]->abort if $_[0][0];
}

END {
    $globaldestroy = 1;
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
