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

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}

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

sub unlock {
    my ($self) = @_;
    my @paths = $self->{checkout}->find ('/', {lock => $$});
    $self->{checkout}->store ($_, {lock => undef})
	for @paths;
}

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

sub giant_unlock {
    my ($self) = @_;
    return unless $self->{giantlock};
    unlink ($self->{giantlock});
    delete $self->{giantlocked};
}

my %REPOS;
my $REPOSPOOL = SVN::Pool->new;

sub open_repos {
    my ($repospath) = @_;
    $REPOS{$repospath} ||= SVN::Repos::open ($repospath, $REPOSPOOL);
}

sub find_repos {
    my ($self, $depotpath, $open) = @_;
    die loc("no depot spec") unless $depotpath;
    my ($depot, $path) = $depotpath =~ m|^/(\w*)(/.*)/?$|
	or die loc("invalid depot spec");

    my $repospath = $self->{depotmap}{$depot} or die loc("no such depot: %1", $depot);

    return ($repospath, $path, $open && open_repos ($repospath));
}

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
    my ($txn, $root) = create_xd_root (@_);
    bless [$txn, $root], 'SVK::XD::Root';
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
    my ($anchor, $target) = ($arg{path}, '');
    $arg{target_path} ||= $arg{path};
    my ($tanchor, $ttarget) = ($arg{target_path}, '');

    print loc("Syncing %1(%2) in %3 to %4.\n", @arg{qw( depotpath path copath rev )});
    unless ($xdroot->check_path ($arg{path}) == $SVN::Node::dir) {
	($anchor, $target, $tanchor, $ttarget) =
	    get_anchor (1, $arg{path}, $arg{target_path});
    }
    else {
	# no anchor
	mkdir ($arg{copath})
	    unless $arg{check_only};
    }

    my $newroot = $fs->revision_root ($arg{rev});
    my ($storage, %cb) = $self->get_editor (%arg,
					    oldroot => $xdroot,
					    newroot => $newroot,
					    anchor => $anchor,
					    target => $target,
					    update => 1);

    $storage = SVK::Editor::Delay->new ($storage);
    my $editor = SVK::Editor::Merge->new (send_fulltext => 1,
					  anchor => $tanchor,
					  target => $ttarget,
					  base_anchor => $anchor,
					  base_root => $xdroot,
					  storage => $storage,
					  %cb);
    $editor->{external} = $ENV{SVKMERGE}
	if $ENV{SVKMERGE} && -x $ENV{SVKMERGE} && !$self->{check_only};
    SVN::Repos::dir_delta ($xdroot->[1], $anchor, $target,
			   $newroot, $arg{target_path},
			   $editor, undef,
			   1, $arg{recursive}, 0, 1);

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

sub do_revert {
    my ($self, %arg) = @_;
    my $xdroot = $self->xdroot (%arg);
    my $storeundef = {'.schedule' => undef,
		      scheduleanchor => undef,
		      '.copyfrom' => undef,
		      '.copyfrom_rev' => undef,
		      '.newprop' => undef};

    my $unschedule = sub {
	$self->{checkout}->store ($_[1], $storeundef);
	print loc("Reverted %1\n", $_[1]);
    };
    my $revert = sub {
	# XXX: need to repsect copied resources
	my $kind = $xdroot->check_path ($_[0]);
	if ($kind == $SVN::Node::none) {
	    print loc("%1 is not versioned; ignored.\n", $_[1]);
	    return;
	}
	if ($kind == $SVN::Node::dir) {
	    mkdir $_[1] unless -e $_[1];
	}
	else {
	    my $fh = get_fh ($xdroot, '>', $_[0], $_[1]);
	    my $content = $xdroot->file_contents ($_[0]);
	    slurp_fh ($content, $fh);
	    close $fh;
	}
	$unschedule->(@_);
    };

    my $revert_item = sub {
	exists $self->{checkout}->get ($_[1])->{'.schedule'} ?
	    &$unschedule (@_) : &$revert (@_);
    };

    if ($arg{recursive}) {
	$self->checkout_delta ( %arg,
				xdroot => $xdroot,
				targets => $arg{targets},
				delete_verbose => 1,
				absent_verbose => 1,
				editor => SVK::Editor::Status->new
				( notify => SVK::Notify->new
				  ( cb_flush => sub {
					my ($path, $status) = @_;
					my $st = $status->[0];
					my $dpath = $path ? "$arg{path}/$path" : $arg{path};
					my $copath = $path ? "$arg{copath}/$path" : $arg{copath};
					if ($st eq 'M' || $st eq 'D' || $st eq '!' || $st eq 'R') {
					    $revert->($dpath, $copath);
					}
					else {
					    $unschedule->($dpath, $copath);
					}
				    },
				  ),
				));
    }
    else {
	if ($arg{targets}) {
	    &$revert_item ("$arg{path}/$_", "$arg{copath}/$_")
		for @{$arg{targets}};
	}
	else {
	    &$revert_item ($arg{path}, $arg{copath});
	}
    }
}

use Regexp::Shellish qw( :all ) ;
# XXX: checkout_delta is getting too complicated and too many options

sub ignore {
    no warnings;
    my @ignore = qw/*.o #*# .#* *.lo *.la .*.rej *.rej .*~ *~ .DS_Store
		    svk-commit*.tmp/;

    return join('|', map {compile_shellish $_} (@ignore, @_));
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
    find (sub {
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
	  }, defined $arg{targets} ?
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
    $arg{add} = 1 if $arg{auto_add} && $arg{kind} == $SVN::Node::none ||
	$schedule eq 'replace';
    my $rev = $arg{cb_rev}->($arg{entry});
    if ($arg{cb_conflict} && $cinfo->{'.conflict'}) {
	$arg{cb_conflict}->($arg{editor}, $arg{entry}, $arg{baton});
    }

    return if $self->_node_deleted_or_absent (%arg, pool => $pool, rev => $rev,
					      type => 'file');

    $rev = 0 if $arg{add};
    my $fh = get_fh ($arg{xdroot}, '<', $arg{path}, $arg{copath});
    my $mymd5 = md5($fh);
    my $md5;

    return unless $schedule || $arg{add} ||
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

    $arg{base} = 0 if $schedule eq 'replace';

    if ($arg{base}) {
	$entries = $arg{base_root}->dir_entries ($arg{base_path})
	    if $arg{kind} == $SVN::Node::dir;
    }
    $baton ||= $arg{root} ? $arg{baton} : $arg{editor}->open_directory ($arg{entry}, $arg{baton}, $rev, $pool);

    if (($schedule eq 'prop' || $arg{add}) && (!defined $targets)) {
	my $newprop = $cinfo->{'.newprop'};
	$arg{editor}->change_dir_prop ($baton, $_, $newprop->{$_}, $pool)
	    for sort keys %$newprop;
    }

    for (sort keys %{$entries}) {
	my $kind = $entries->{$_}->kind;
	my $delta = ($kind == $SVN::Node::file) ? \&_delta_file : \&_delta_dir;
	$self->$delta ( %arg,
			add => 0,
			base => 1,
			depth => $arg{depth} ? $arg{depth} - 1: undef,
			entry => $arg{entry} ? "$arg{entry}/$_" : $_,
			kind => $kind,
			targets => $targets ? $targets->{$_} : undef,
			baton => $baton,
			root => 0,
			cinfo => undef,
			base_path => "$arg{base_path}/$_",
			path => "$arg{path}/$_",
			copath => "$arg{copath}/$_")
	    if !defined $targets || exists $targets->{$_};
    }

    # check scheduled addition
    opendir my ($dir), $arg{copath};

    if ($dir) {

    my $svn_ignore = $self->get_props ($arg{xdroot}, $arg{path},
				       $arg{copath})->{'svn:ignore'}
        if $arg{kind} == $SVN::Node::dir;
    my $ignore = ignore (split ("\n", $svn_ignore || ''));
    for (sort grep { !m/^\.+$/ && !exists $entries->{$_} } readdir ($dir)) {
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
			path => $ccinfo->{'.copyfrom'} || "$arg{path}/$_",
			# XXX: what shold base_path be when there's copyfrom?
			base_path => $ccinfo->{'.copyfrom'} || "$arg{base_path}/$_",
			copyfrom => $ccinfo->{'.copyfrom'},
			cinfo => $ccinfo )
	    if !defined $targets || exists $targets->{$_};

    }

    closedir $dir;

    }

    # chekc prop diff
    $arg{editor}->close_directory ($baton, $pool)
	unless $arg{root} || $schedule eq 'delete';
}

sub _get_rev {
    my ($self, $path) = @_;
    $self->{checkout}->get($path)->{revision};
}


# options:
#  delete_verbose: generate delete_entry calls for subdir within deleted entry
#  absent_verbose: generate absent_* calls for subdir within absent entry
#  unknown_verbose: generate cb_unknown calls for subdir within absent entry
#  absent_ignore: don't generate absent_* calls.

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

sub do_import {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my $root = $fs->revision_root ($yrev);
    my $kind = $root->check_path ($arg{path});

    die loc("import destination cannot be a file") if $kind == $SVN::Node::file;

    if ($kind == $SVN::Node::none) {
	my $edit = SVN::Simple::Edit->new
	    (_editor => [SVN::Repos::get_commit_editor($arg{repos},
					    "file://$arg{repospath}",
					    '/', $ENV{USER},
					    "directory for svk import",
					    sub { print loc("Import path %1 initialized.\n", $arg{path}) })],
	     missing_handler => &SVN::Simple::Edit::check_missing ($root));

	$edit->open_root ($yrev);
	$edit->add_directory ($arg{path});
	$edit->close_edit;
	$yrev = $fs->youngest_rev;
	$root = $fs->revision_root ($yrev);
    }

    my $editor = $arg{check_only} ? SVN::Delta::Editor->new :
	SVN::Delta::Editor->new
	( SVN::Repos::get_commit_editor
	  ( $arg{repos},
	    "file://$arg{repospath}",
	    $arg{path}, $ENV{USER},
	    $arg{message},
	    sub { $yrev = $_[0];
		  print loc("Directory %1 imported to depotpath %2 as revision %3.\n",
			    $arg{copath}, $arg{depotpath}, $yrev) }));

    my $baton = $editor->open_root ($yrev);

    if (exists $self->{checkout}->get ($arg{copath})->{depotpath}) {
	$arg{is_checkout}++;
	die loc("Import source cannot be a checkout path")
	    unless $arg{force};
    }
    else {
	# XXX: check the entry first
	$self->{checkout}->store ($arg{copath},
				  {depotpath => $arg{depotpath},
				   '.newprop' => undef,
				   '.conflict' => undef,
				   revision =>0});
    }

    $self->_delta_dir ( %arg,
	        auto_add => 1,
		base => 1,
		cb_rev => sub { $yrev },
		editor => $editor,
		base_root => $root,
		base_path => $arg{path},
		xdroot => $root,
		kind => $SVN::Node::dir,
		absent_as_delete => 1,
		baton => $baton, root => 1);

    $editor->close_directory ($baton);

    $editor->close_edit ();

    if ($arg{is_checkout}) {
	my (undef, $path) = $self->find_repos_from_co ($arg{copath}, 0);
	$self->{checkout}->store_recursively ($arg{copath},
					      {revision => $yrev,
					       '.copyfrom' => undef,
					       '.copyfrom_rev' => undef,
					       '.schedule' => undef})
	    if $path eq $arg{path};
    }
    else {
	$self->{checkout}->store ($arg{copath},
				  {depotpath => undef,
				   revision => undef,
				   '.schedule' => undef})
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
