package SVK::XD;
use strict;
our $VERSION = $SVK::VERSION;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
require SVN::Delta;
require SVK::Editor::Merge;
use SVK::Editor::Status;
use SVK::Editor::Delay;
use SVK::Editor::XD;
use SVK::I18N;
use SVK::Util qw( slurp_fh md5 get_anchor );
use Data::Hierarchy '0.18';
use File::Spec;
use File::Find;
use File::Path;
use YAML qw(LoadFile DumpFile);
use PerlIO::via::dynamic;

=head1 NAME

SVK::XD - svk depot and checkout handling.

=head1 SYNOPSIS

  use SVK::XD;
  $xd = SVK::XD->new
      (depotmap => { '' => '/path/to/repos'},
       checkout => Data::Hierarchy->new);

=head1 DESCRIPTION

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
    $self->{signature} ||= SVK::XD::Signature->new (root => "$self->{svkpath}/cache")
	if $self->{svkpath};
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

    mkdir($self->{svkpath}) || die loc("Cannot create svk-config-directory: $!")
        unless -d $self->{svkpath};

    $self->giant_lock ();

    if (-e $self->{statefile}) {
	$info = LoadFile ($self->{statefile});
    }

    $info ||= { depotmap => {'' => "$self->{svkpath}/local" },
	        checkout => Data::Hierarchy->new() };
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
    my @paths = $self->{checkout}->find ('/', {lock => $$});
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

    if (-e $self->{giantlock}) {
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

=item find_repos

Given depotpath and an option about if the repository should be
opened. Returns an array of repository path, the path inside
repository, and the C<SVN::Repos> object if caller wants the
repository to be opened.

=cut

sub find_repos {
    my ($self, $depotpath, $open) = @_;
    die loc("no depot spec") unless $depotpath;
    my ($depot, $path) = $depotpath =~ m|^/(\w*)(/.*)/?$|
	or die loc("invalid depot spec");

    my $repospath = $self->{depotmap}{$depot} or die loc("no such depot: %1", $depot);

    return ($repospath, $path, $open && _open_repos ($repospath));
}

=item find_repos_from_co

Given the checkout path and an optiona bout if the repository should
be opened. Returns an array of repository path, the path inside
repository, the absolute checkout path, the checkout info, and the
C<SVN::Repos> object if caller wants the repository to be opened.

=cut

sub find_repos_from_co {
    my ($self, $copath, $open) = @_;
    $copath = Cwd::abs_path ($copath || '');

    my ($cinfo, $coroot) = $self->{checkout}->get ($copath);
    die loc("path %1 is not a checkout path", $copath) unless %$cinfo;
    my ($repospath, $path, $repos) = $self->find_repos ($cinfo->{depotpath}, $open);

    if ($copath eq $coroot) {
	$copath = '';
    }
    else {
	$copath =~ s|^\Q$coroot\E/|/|;
    }

    return ($repospath, $path eq '/' ? $copath || '/' : $path.$copath,
	    $cinfo, $repos);
}

=item find_repos_from_co_maybe

Like C<find_repos_from_co>, but falls back to see if the given path is
a depotpath. In that case, the checkout paths returned iwll be undef.

=cut

sub find_repos_from_co_maybe {
    my ($self, $target, $open) = @_;
    my ($repospath, $path, $copath, $cinfo, $repos);
    local $@;
    unless (($repospath, $path, $repos) = eval { $self->find_repos ($target, $open) }) {
	($repospath, $path, $cinfo, $repos) = $self->find_repos_from_co ($target, $open);
	$copath = Cwd::abs_path ($target || '');
    }
    return ($repospath, $path, $copath, $cinfo, $repos);
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
    my @targets = map {Cwd::abs_path ($_ || '')} @_;
    my ($anchor, $report);
    $report = $_[0];
    for (@targets) {
	if (!$anchor) {
	    $anchor = $_;
	    $report = $_[0]
	}
	my $cinfo = $self->{checkout}->get ($anchor);
	my $schedule = $cinfo->{'.schedule'} || '';
	if ($anchor ne $_ || -f $anchor || $cinfo->{scheduleanchor} ||
	    $schedule eq 'add' || $schedule eq 'delete') {
	    while ($anchor.'/' ne substr ($_, 0, length($anchor)+1) ||
		   $self->{checkout}->get ($anchor)->{scheduleanchor}) {
		($anchor, $report) = get_anchor (0, $anchor, $report);
	    }
	}
    }
    $report .= '/' unless $report eq '' || substr($report, -1, 1) eq '/';
    return ($report, $anchor,
	    map {s|^\Q$anchor\E/||;$_} grep {$_ ne $anchor} @targets);
}

sub xdroot {
    SVK::XD::Root->new (create_xd_root (@_));
}

sub create_xd_root {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my ($txn, $root);

    my @paths = $self->{checkout}->find ($arg{copath}, {revision => qr'.*'});

    return (undef, $fs->revision_root
	    ($self->{checkout}->get ($paths[0] || $arg{copath})->{revision}))
	if $#paths <= 0;

    for (@paths) {
	my $cinfo = $self->{checkout}->get ($_);
	unless ($root) {
	    $txn = $fs->begin_txn ($cinfo->{revision});
	    $root = $txn->root();
	    next if $_ eq $arg{copath};
	}
	s|^\Q$arg{copath}\E/||;
	$root->make_dir ($arg{path})
	    if $root->check_path ($arg{path}) == $SVN::Node::none;
	if ($cinfo->{'.deleted'}) {
	    $root->delete ("$arg{path}/$_");
	}
	else {
	    SVN::Fs::revision_link ($fs->revision_root ($cinfo->{revision}),
				    $root, "$arg{path}/$_");
	}
    }
    return ($txn, $root);
}

=head2 Checkout handling

=over

=cut

sub translator {
    my ($target) = @_;
    $target .= '/' if $target;
    $target ||= '';
    return qr/^\Q$target\E/;
}

sub xd_storage_cb {
    my ($self, %arg) = @_;
    # translate to abs path before any check
    return
	( cb_exist => sub { $_ = shift; $arg{get_copath} ($_); -e $_},
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
			       my $base = get_fh ($arg{oldroot}, '<',
						  "$arg{anchor}/$path", $copath);
			       my $md5 = md5 ($base);
			       return undef if $md5 eq $checksum;
			       seek $base, 0, 0;
			       return [$base, undef, $md5];
			   },
	  cb_dirdelta => sub { my ($path, $base_root, $base_path, $pool) = @_;
			       my $copath = $path;
			       $arg{get_copath} ($copath);
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
				     path => "$arg{path}/$path",
				     copath => $copath,
				     base_root => $base_root,
				     base_path => $base_path,
				     xdroot => $arg{oldroot},
				     nodelay => 1,
				     depth => 1,
				     editor => $editor,
				     cb_unknown =>
				     sub { # XXX: unkonwn as added?
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
    my $t = translator($arg{target});
    $arg{get_copath} = sub { $_[0] = $arg{copath}, return
				 if $arg{target} eq $_[0];
			     $_[0] =~ s|$t|$arg{copath}/|
				 or die loc("unable to translate %1 with %2", $_[0], $t);
			     $_[0] =~ s|/$||;
			 };
    my $storage = SVK::Editor::XD->new (%arg, xd => $self);

    return wantarray ? ($storage, $self->xd_storage_cb (%arg)) : $storage;
}

sub do_update {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;

    my $xdroot = $self->xdroot (%arg);
    my ($anchor, $target, $report) = ($arg{path}, '', $arg{report});
    $arg{target_path} ||= $arg{path};
    my ($tanchor, $ttarget) = ($arg{target_path}, '');

    print loc("Syncing %1(%2) in %3 to %4.\n", @arg{qw( depotpath path copath rev )});
    unless ($xdroot->check_path ($arg{path}) == $SVN::Node::dir) {
	($anchor, $target, $tanchor, $ttarget, $report) =
	    get_anchor (1, $arg{path}, $arg{target_path}, $arg{report});
    }
    else {
	# no anchor
	mkdir ($arg{copath})
	    unless $arg{check_only};
    }
    # XXX: use SVK::Merge
    my $newroot = $fs->revision_root ($arg{rev});
    my ($storage, %cb) = $self->get_editor (%arg,
					    oldroot => $xdroot,
					    newroot => $newroot,
					    anchor => $anchor,
					    target => $target,
					    update => 1);

    $storage = SVK::Editor::Delay->new ($storage);
    $report .= '/' if $report ne '' && substr($report, -1, 1) ne '/';
    my $editor = SVK::Editor::Merge->new (send_fulltext => 1,
					  report => $report,
					  anchor => $tanchor,
					  target => $ttarget,
					  base_anchor => $anchor,
					  base_root => $xdroot,
					  storage => $storage,
					  %cb);
    $editor->{external} = $ENV{SVKMERGE}
	if $ENV{SVKMERGE} && -x $ENV{SVKMERGE} && !$self->{check_only};
    $self->depot_delta (oldroot => $xdroot, newroot => $newroot,
			oldpath => [$anchor, $target], newpath => $arg{target_path},
			editor => $editor, no_recurse => !$arg{recursive});

    print loc("%*(%1,conflict) found.\n", $editor->{conflicts}) if $editor->{conflicts};
}

sub do_add {
    my ($self, %arg) = @_;

    if ($arg{recursive}) {
	my $xdroot = $self->xdroot (%arg);
	$self->checkout_delta ( %arg,
				xdroot => $xdroot,
				editor => SVK::Editor::Status->new
				( notify => SVK::Notify->new
				  ( cb_flush => sub {
					my ($path, $status) = @_;
					my $copath = $path ? "$arg{copath}/$path" : $arg{copath};
					if ($status->[0] eq 'D' && -e $copath) {
					    $self->{checkout}->store ($copath, { '.schedule' => 'replace' });
					    print "R   $arg{report}$path\n" unless $arg{quiet};
					}
				    })),
				delete_verbose => 1,
				unknown_verbose => 1,
				cb_unknown => sub {
				    $self->{checkout}->store ($_[1], { '.schedule' => 'add' });
				    print "A   $arg{report}$_[0]\n" unless $arg{quiet};
				},
			      );
    }
    else {
	die "do_add with targets and non-recursive not handled" if $arg{targets};
	$self->{checkout}->store ($arg{copath}, { '.schedule' => 'add',
						  '.copyfrom' => $arg{copyfrom},
						  '.copyfrom_rev' => $arg{copyfrom_rev},
						});
	print "A   $arg{report}\n" unless $arg{quiet};
    }
}

sub do_delete {
    my ($self, %arg) = @_;
    my $xdroot = $self->xdroot (%arg);
    my @deleted;

    # check for if the file/dir is modified.
    $self->checkout_delta ( %arg,
			    xdroot => $xdroot,
			    absent_as_delete => 1,
			    delete_verbose => 1,
			    absent_verbose => 1,
			    editor => SVK::Editor::Status->new
			    ( notify => SVK::Notify->new
			      ( cb_flush => sub {
				    my ($path, $status) = @_;
				    my $rpath = "$arg{report}$path";
				    my $st = $status->[0];
				    if ($st eq 'M') {
					die loc("%1 changed", $rpath);
				    }
				    elsif ($st eq 'D') {
					push @deleted, "$arg{copath}/$path";
				    }
				    elsif (-f $rpath) {
					die loc("%1 is scheduled, use 'svk revert'", $rpath);
				    }
				})),
			    cb_unknown => sub {
				die loc("%1 is not under version control", $_[0]);
			    }
			  );

    # actually remove it from checkout path
    my @paths = grep {-e $_} ($arg{targets} ?
			      map { "$arg{copath}/$_" } @{$arg{targets}}
			      : $arg{copath});
    find(sub {
	     my $cpath = $File::Find::name;
	     no warnings 'uninitialized';
	     return if $self->{checkout}->get ($cpath)->{'.schedule'}
		 eq 'delete';
	     push @deleted, $cpath;
	 }, @paths) if @paths;

    for (@deleted) {
	my $rpath = $_;
	$rpath =~ s|^\Q$arg{copath}\E/|$arg{report}|;
	print "D   $rpath\n" unless $arg{quiet};
	$self->{checkout}->store ($_, {'.schedule' => 'delete'});
    }

    rmtree (\@paths) if @paths;
}

sub do_proplist {
    my ($self, %arg) = @_;

    my $props = {};
    my $xdroot = $arg{rev} ? $arg{repos}->fs->revision_root ($arg{rev})
	: $self->xdroot (%arg);

    $props = $self->get_props ($xdroot, $arg{path},
			       $arg{rev} ? undef : $arg{copath})
	if $xdroot;

    return $props;
}

sub do_propset {
    my ($self, %arg) = @_;
    my ($xdroot, %values);
    my $entry = $self->{checkout}->get ($arg{copath});
    $entry->{'.schedule'} ||= '';
    $entry->{'.newprop'} ||= {};

    unless ($entry->{'.schedule'} eq 'add' || !$arg{repos}) {
	$xdroot = $self->xdroot (%arg);

	die loc("%1(%2) is not under version control", $arg{copath}, $arg{path})
	    if $xdroot->check_path ($arg{path}) == $SVN::Node::none;
    }

    #XXX: support working on multiple paths and recursive
    die loc("%1 is already scheduled for delete", $arg{copath})
	if $entry->{'.schedule'} eq 'delete';
    %values = %{$entry->{'.newprop'}}
	if exists $entry->{'.schedule'};
    $self->{checkout}->store ($arg{copath},
			      { '.schedule' => $entry->{'.schedule'} || 'prop',
				'.newprop' => {%values,
					    $arg{propname} =>
					    $arg{propvalue},
					   }});
    print " M $arg{copath}\n" unless $arg{quiet};

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
    chmod ($mode, $copath)
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

=back

=cut

use Regexp::Shellish qw( :all ) ;
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

    my $handle = $arg{editor}->apply_textdelta ($arg{baton}, undef, $arg{pool});
    return unless $handle && $#{$handle} > 0;

    if ($arg{send_delta} && $arg{base}) {
	my $spool = SVN::Pool->new_default ($arg{pool});
	my $source = $arg{xdroot}->file_contents ($arg{path}, $spool);
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
    find ({ preprocess => sub { sort @_ },
	    wanted =>
	    sub {
	      return if m/$ignore/;
	      my $dpath = $File::Find::name;
	      my $copath = $dpath;
	      my $schedule = $self->{checkout}->get ($copath)->{'.schedule'} || '';
	      return if $schedule eq 'delete';
	      if ($arg{entry}) {
		  $dpath =~ s/^\Q$arg{copath}\E/$arg{entry}/;
	      }
	      else {
		  if ($dpath eq $arg{copath}) {
		      $dpath = '';
		  }
		  else {
		      $dpath =~ s|^\Q$arg{copath}\E/||;
		  }
	      }
	      $arg{cb_unknown}->($dpath, $File::Find::name);
	  }}, defined $arg{targets} ?
	  map {"$arg{copath}/$_"} @{$arg{targets}} : $arg{copath});
}

sub _node_deleted_or_absent {
    my ($self, %arg) = @_;
    my $schedule = $arg{cinfo}{'.schedule'} || '';

    if ($schedule eq 'delete' || $schedule eq 'replace') {
	$arg{editor}->delete_entry (@arg{qw/entry rev baton pool/});

	if ($arg{type} ne 'file') {
	    # XXX: should still be recursion since the entries
	    # XXX: check with xdroot since this might be deleted when from base_root to xdroot
	    if ($arg{delete_verbose}) {
		for ($self->{checkout}->find
		     ($arg{copath}, {'.schedule' => 'delete'})) {
		    s|^\Q$arg{copath}\E/?||;
		    $arg{editor}->delete_entry ("$arg{entry}/$_", @arg{qw/rev baton pool/})
			if $_;
		}
	    }
	    $self->_unknown_verbose (%arg)
		if $arg{cb_unknown} && $arg{unknown_verbose};
	}
	return 1 if $schedule eq 'delete';
    }

    unless (-e $arg{copath}) {
	return 1 if $arg{absent_ignore};
	if ($arg{absent_as_delete}) {
	    $arg{editor}->delete_entry (@arg{qw/entry rev baton pool/});
	}
	else {
	    my $func = "absent_$arg{type}";
	    $arg{editor}->$func (@arg{qw/entry baton pool/});
	}
	return 1 unless $arg{type} ne 'file' && $arg{absent_verbose};
    }
    return 0;
}

sub _delta_file {
    my ($self, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $cinfo = $arg{cinfo} ||= $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';
    my $modified;
    $arg{add} = 1 if $arg{auto_add} && $arg{kind} == $SVN::Node::none ||
	$schedule eq 'replace';
    my $rev = $arg{cb_rev}->($arg{entry});
    if ($arg{cb_conflict} && $cinfo->{'.conflict'}) {
	++$modified;
	$arg{cb_conflict}->($arg{editor}, $arg{entry}, $arg{baton});
    }

    return 1 if $self->_node_deleted_or_absent (%arg, pool => $pool, rev => $rev,
						type => 'file');

    $rev = 0 if $arg{add};
    my $fh = get_fh ($arg{xdroot}, '<', $arg{path}, $arg{copath});
    my $mymd5 = md5($fh);
    my $md5;

    return $modified unless $schedule || $arg{add} ||
	($arg{base} && $mymd5 ne ($md5 = $arg{base_root}->file_md5_checksum ($arg{base_path})));

    my $baton = $arg{add} ?
	$arg{editor}->add_file ($arg{entry}, $arg{baton},
				$cinfo->{'.copyfrom'} ?
				"file://$arg{repospath}$cinfo->{'.copyfrom'}" : undef,
				$cinfo->{'.copyfrom_rev'} ||  -1, $pool) :
				    undef;
    my $newprop = $cinfo->{'.newprop'};
    $baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $rev, $pool)
	if keys %$newprop;

    $arg{editor}->change_file_prop ($baton, $_, $newprop->{$_}, $pool)
	for sort keys %$newprop;

    if (!$arg{base} ||
	$mymd5 ne ($md5 ||= $arg{base_root}->file_md5_checksum ($arg{base_path}))) {
	seek $fh, 0, 0;
	$baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $rev, $pool);
	$self->_delta_content (%arg, baton => $baton, fh => $fh, pool => $pool);
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
    $arg{add} = 1 if $arg{auto_add} && $arg{kind} == $SVN::Node::none ||
	$schedule eq 'replace';
    my $rev = $arg{cb_rev}->($arg{entry} || '');

    # compute targets for children
    my $targets;
    for (@{$arg{targets} || []}) {
	my ($a, $b) = m|^(.*?)(?:/(.*))?$|;
	if ($b) {
	    push @{$targets->{$a}}, $b
	}
	else {
	    $targets->{$a} = undef;
	}
    }
    return if $self->_node_deleted_or_absent (%arg, pool => $pool, rev => $rev,
					      type => 'directory');
    $rev = 0 if $arg{add};
    $arg{base} = 0 if $schedule eq 'replace';
    my ($entries, $baton) = ({});
    if ($arg{add}) {
	$baton = $arg{root} ? $arg{baton} :
	    $arg{editor}->add_directory ($arg{entry}, $arg{baton},
					 $arg{copyfrom} ?
					 ("file://$arg{repospath}$arg{copyfrom}",
					  $cinfo->{'.copyfrom_rev'}) : (undef, -1), $pool);
    }

    $entries = $arg{base_root}->dir_entries ($arg{base_path})
	if $arg{base} && $arg{kind} == $SVN::Node::dir;

    $baton ||= $arg{root} ? $arg{baton} : $arg{editor}->open_directory ($arg{entry}, $arg{baton}, $rev, $pool);

    if (($schedule eq 'prop' || $arg{add}) && (!defined $targets)) {
	my $newprop = $cinfo->{'.newprop'};
	$arg{editor}->change_dir_prop ($baton, $_, $newprop->{$_}, $pool)
	    for sort keys %$newprop;
    }

    my $signature;
    if ($self->{signature} && $arg{xdroot} eq $arg{base_root}) {
	$signature = $self->{signature}->load ($arg{copath});
    }

    # XXX: Merge this with @direntries so we have single entry to descendents
    for my $entry (sort keys %$entries) {
	next if defined $targets && !exists $targets->{$entry};
	my $kind = $entries->{$entry}->kind;
	my $ccinfo = $self->{checkout}->get ("$arg{copath}/$entry");
	my $sche = $ccinfo->{'.schedule'} || '';
	next if $kind == $SVN::Node::file && $signature && !$signature->changed ($entry)
	    && !$sche;
	my $delta = ($kind == $SVN::Node::file) ? \&_delta_file : \&_delta_dir;
	$self->$delta ( %arg,
			add => 0,
			base => 1,
			depth => $arg{depth} ? $arg{depth} - 1: undef,
			entry => $arg{entry} ? "$arg{entry}/$entry" : $entry,
			kind => $kind,
			targets => $targets ? $targets->{$entry} : undef,
			baton => $baton,
			root => 0,
			cinfo => undef,
			base_path => "$arg{base_path}/$entry",
			path => $arg{path} eq '/' ? "/$entry" : "$arg{path}/$entry",
			copath => "$arg{copath}/$entry") and ($signature && $signature->invalidate ($entry));
    }

    $signature->flush ($arg{copath}) if $signature;

    # check scheduled addition
    my $ignore = ignore ($arg{add} ? () :
			 split ("\n", $self->get_props
				($arg{xdroot}, $arg{path},
				 $arg{copath})->{'svn:ignore'} || ''));

    opendir my ($dir), $arg{copath} or die "$arg{copath}: $!";
    my @direntries = sort grep { !m/^\.+$/ && !exists $entries->{$_} } readdir ($dir);
    closedir $dir;

    for (@direntries) {
	next if m/$ignore/;
	my $ccinfo = $self->{checkout}->get ("$arg{copath}/$_");
	my $sche = $ccinfo->{'.schedule'} || '';
	my $add = ($sche || $arg{auto_add}) ||
	    ($arg{xdroot} ne $arg{base_root} &&
	     $arg{xdroot}->check_path ("$arg{path}/$_") != $SVN::Node::none);
	my %newpaths = ( copath => "$arg{copath}/$_",
			 entry => $arg{entry} ? "$arg{entry}/$_" : $_,
			 path => "$arg{path}/$_",
			 targets => $targets ? $targets->{$_} : undef);
	unless ($add) {
	    if ($arg{cb_unknown} &&
		(!defined $targets || exists $targets->{$_})) {
		if ($arg{unknown_verbose}) {
		    $self->_unknown_verbose (%arg, %newpaths);
		}
		else {
		    $arg{cb_unknown}->("$arg{path}/$_", "$arg{copath}/$_")
			if $arg{cb_unknown};
		}

	    }
	    next;
	}
	my $delta = (-d "$arg{copath}/$_") ? \&_delta_dir : \&_delta_file;
	my $kind = $ccinfo->{'.copyfrom'} ?
	    $arg{xdroot}->check_path ($ccinfo->{'.copyfrom'}) : $SVN::Node::none;
	$self->$delta ( %arg,
			%newpaths,
			add => $add,
			base => exists $ccinfo->{'.copyfrom'},
			kind => $kind,
			baton => $baton,
			root => 0,
			path => $ccinfo->{'.copyfrom'} ||
			($arg{path} eq '/' ? "/$_" : "$arg{path}/$_"),
			# XXX: what shold base_path be when there's copyfrom?
			base_path => $ccinfo->{'.copyfrom'} || "$arg{base_path}/$_",
			copyfrom => $ccinfo->{'.copyfrom'},
			cinfo => $ccinfo )
	    if !defined $targets || exists $targets->{$_};
    }

    # chekc prop diff
    $arg{editor}->close_directory ($baton, $pool)
	unless $arg{root} || $schedule eq 'delete';
    return 0;
}

sub _get_rev {
    my ($self, $path) = @_;
    $self->{checkout}->get($path)->{revision};
}

sub checkout_delta {
    my ($self, %arg) = @_;
    $arg{base_root} ||= $arg{xdroot};
    $arg{base_path} ||= $arg{path};
    my $kind = $arg{kind} = $arg{base_root}->check_path ($arg{base_path});
    my $copath = $arg{copath};
    $arg{editor} = SVK::Editor::Delay->new ($arg{editor})
	unless $arg{nodelay};
    $arg{editor} = SVN::Delta::Editor->new (_debug => 1, _editor => [$arg{editor}])
	if $arg{debug};
    $arg{cb_rev} ||= sub { my $target = shift;
			   $target = $target ? "$copath/$target" : $copath;
			   $self->_get_rev ($target);
		       };
    my $rev = $arg{cb_rev}->('');
    my $baton = $arg{editor}->open_root ($rev);

    if ($kind == $SVN::Node::file) {
	$self->_delta_file (%arg, baton => $baton, base => 1);
    }
    elsif ($kind == $SVN::Node::dir) {
	$self->_delta_dir (%arg, baton => $baton, root => 1, base => 1);
    }
    else {
	my $delta = (-d $arg{copath}) ? \&_delta_dir : \&_delta_file;
	my $sche =
	    $self->{checkout}->get ($arg{copath})->{'.schedule'} || '';

	if ($sche eq 'add') {
	    $self->$delta ( %arg, add => 1, baton => $baton, root => 1);
	}
	else {
	    if ($arg{unknown_verbose}) {
		$arg{cb_unknown}->('', $arg{copath})
		    if $arg{targets};
		$self->_unknown_verbose (%arg);
	    }
	    else {
		$arg{cb_unknown}->($arg{path}, $arg{copath})
		    if $arg{cb_unknown};
	    }
	}
    }

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

sub get_keyword_layer {
    my ($root, $path) = @_;
    my $pool = SVN::Pool->new_default;
    local $@;
    my $k = eval { $root->node_prop ($path, 'svn:keywords') };
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
		       my $rev = 1;
		       my $fs = $root->fs;
		       my $hist = $fs->revision_root ($fs->youngest_rev)->node_history ($path);
		       $rev++ while ($hist = $hist->prev (1));
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
	Revision	    FileRev
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
         sub { $_[1] =~ s/\$($keyword)\b[-#:\w\t \.\/]*\$/"\$$1: ".$kmap{$1}->($root, $path).' $'/eg },
	 untranslate =>
	 sub { $_[1] =~ s/\$($keyword)\b[-#:\w\t \.\/]*\$/\$$1\$/g});
}

sub get_fh {
    my ($root, $mode, $path, $fname, $layer) = @_;
    $layer ||= get_keyword_layer ($root, $path);
    open my ($fh), $mode, $fname;
    $layer->via ($fh) if $layer;
    return $fh;
}

sub get_props {
    my ($self, $root, $path, $copath) = @_;

    my ($props, $entry) = ({});

    $entry = $self->{checkout}->get ($copath) if $copath;
    $entry->{'.newprop'} ||= {};
    $entry->{'.schedule'} ||= '';

    unless ($entry->{'.schedule'} eq 'add') {

	die loc("path %1 not found", $path)
	    if $root->check_path ($path) == $SVN::Node::none;
	$props = $root->node_proplist ($path);
    }

    return {%$props,
	    %{$entry->{'.newprop'}}};


}

sub DESTROY {
    my ($self) = @_;
    return if $self->{updated};
    $self->store ();
}

package SVK::XD::Signature;

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, __PACKAGE__;
    %$self = @arg;
    mkdir ($self->{root}) unless -e $self->{root};
    return $self;
}

sub load {
    my ($factory, $path) = @_;
    my $spath = $path;
    $spath =~ s{/}{_}g;
    my $self = bless { root => $factory->{root},
		       path => $path, spath => $spath }, __PACKAGE__;
    $self->read;
    return $self;
}

sub path {
    my $self = shift;
    return "$self->{root}/$self->{spath}";
}

sub lock_path {
    my $self = shift;
    return $self->path.'_lock';
}

sub lock {
    my ($self) = @_;
    my $path = $self->lock_path;
    return if -e $path;
    open my $fh, '>', $path;
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
        open my $fh, '<', $path or die $!;
        $self->{signature} =  { <$fh> };
    }
    else {
        $self->{signature} = {};
    }

    $self->{newsignature} = {};
}

sub write {
    my ($self) = @_;
    my $path = $self->path;
    # nothing to write
    return unless keys %{$self->{newsignature}};
    # not first time file and no entry changed
    return if -s $path && !keys %{$self->{signature}};

    $self->lock;
    return unless $self->{locked};
    my ($hash, $file) = @_;
    open my $fh, '>', $path or die $!;
    print {$fh} %{ $self->{newsignature} };
    $self->unlock;
}

sub changed {
    my ($self, $entry) = @_;
    my $file = "$self->{path}/$entry";
    # inode, mtime, size
    my @sig = (stat ($file))[1,7,9] or return 1;

    my ($key, $value) = (quotemeta($entry)."\n", "@sig\n");
    $self->{newsignature}{$key} = $value;
    return 1 unless exists $self->{signature}{$key};

    return 1 if $self->{signature}{$key} ne $self->{newsignature}{$key};
    # remove from ->{signature} if unchanged
    delete $self->{signature}{$key};

    return 0;
}

sub invalidate {
    my ($self, $entry) = @_;
    use Carp;
    confess unless $entry;
    delete $self->{newsignature}{quotemeta($entry)."\n"};
}

sub flush {
    my ($self) = @_;
    $self->write;
}

package SVK::XD::Root;
use SVK::I18N;

our $AUTOLOAD;
sub AUTOLOAD {
    my $func = $AUTOLOAD;
    $func =~ s/^SVK::XD::Root:://;
    return if $func =~ m/^[A-Z]*$/;
    no strict 'refs';
    my $self = shift;
    $self->[1]->$func (@_);
}

sub new {
    my ($class, @arg) = @_;
    unshift @arg, undef if $#arg == 0;
    bless [@arg], $class;
}

# XXX: workaround some stalled refs in svn/perl
my $globaldestroy;

sub DESTROY {
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
