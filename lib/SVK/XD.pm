package SVK::XD;
use strict;
our $VERSION = '0.13';
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
require SVN::Delta;
require SVK::MergeEditor;
use SVK::RevertEditor;
use SVK::DelayEditor;
use SVK::DeleteEditor;
use SVK::I18N;
use SVK::Util qw( slurp_fh md5 get_anchor );
use Data::Hierarchy '0.15';
use File::Spec;
use File::Find;
use File::Path;
use YAML qw(LoadFile DumpFile);
use File::Temp qw/:mktemp/;
use PerlIO::via::dynamic;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}

sub load {
    my ($self) = @_;
    my $svkpath = "$ENV{HOME}/.svk";
    my $info;

    $self->giant_lock ();

    if (-e "$svkpath/config") {
	$info = LoadFile ($self->{statefile});
    }
    else {
	mkdir ($svkpath);
    }

    $info ||= { depotmap => {'' => "$svkpath/local" },
	        checkout => Data::Hierarchy->new(),
	      };
    $self->{$_} = $info->{$_} for keys %$info;
}

sub store {
    my ($self) = @_;
    $self->{updated} = 1;
    return unless $self->{statefile};
    my $error = $@;
    if ($self->{giantlocked}) {
	DumpFile ($self->{statefile}, { checkout => $self->{checkout},
					depotmap => $self->{depotmap}} );
    }
    elsif ($self->{modified}) {
	$self->giant_lock ();
	my $info = LoadFile ($self->{statefile});
	my @paths = $info->{checkout}->find ('/', {lock => $$});
	$info->{checkout}->merge ($self->{checkout}, $_)
	    for @paths;
	DumpFile ($self->{statefile}, { checkout => $info->{checkout},
					depotmap => $info->{depotmap}} );
    }
    $self->giant_unlock ();
    $@ = $error;
}

sub lock {
    my ($self, $path) = @_;
    if ($self->{checkout}->get ($path)->{lock}) {
	die loc("%1 already locked, use 'svk cleanup' if lock is stalled", $path);
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

    open my ($lock), '>', $self->{giantlock};
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
    unless (($repospath, $path, $repos) = eval { $self->find_repos ($target, $open) }) {
	undef $@;
	($repospath, $path, $cinfo, $repos) = $self->find_repos_from_co ($target, $open);
	$copath = Cwd::abs_path ($target || '');
    }
    return ($repospath, $path, $copath, $cinfo, $repos);
}

sub find_depotname {
    my ($self, $target, $can_be_co) = @_;
    my ($cinfo);
    if ($can_be_co) {
	(undef, undef, $cinfo) = eval { $self->find_repos_from_co ($target, 0) };
	if ($@) {
	    undef $@;
	}
	else {
	    $target = $cinfo->{depotpath};
	}
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
	my $schedule = $self->{checkout}->get ($anchor)->{'.schedule'} || '';
	if ($anchor ne $_ || -f $anchor ||
	    $schedule eq 'add' || $schedule eq 'delete') {
	    while ($anchor.'/' ne substr ($_, 0, length($anchor)+1)) {
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
			       $arg{get_copath} ($path);
			       my $base = get_fh ($arg{oldroot}, '<',
						  "$arg{anchor}/$arg{path}", $path);
			       my $md5 = md5 ($base);
			       return undef if $md5 eq $checksum;
			       seek $base, 0, 0;
			       return [$base, undef, $md5];
			   });
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
    my $storage = SVK::XD::Editor->new
	( %arg,
	  checkout => $self->{checkout},
	  xd => $self,
	);

    return $storage unless wantarray;

    return ($storage, $self->xd_storage_cb (%arg));
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

    $storage = SVK::DelayEditor->new ($storage);
    my $editor = SVK::MergeEditor->new
	(_debug => 0,
	 fs => $fs,
	 send_fulltext => 1,
	 anchor => $tanchor,
	 target => $ttarget,
	 base_anchor => $anchor,
	 base_root => $xdroot,
	 storage => $storage,
	 %cb
	);

    SVN::Repos::dir_delta ($xdroot->[1], $anchor, $target,
			   $newroot, $arg{target_path},
			   $editor, undef,
			   1, 1, 0, 1);
}

sub do_add {
    my ($self, %arg) = @_;

    if ($arg{recursive}) {
	my $xdroot = $self->xdroot (%arg);
	$self->checkout_delta ( %arg,
				baseroot => $xdroot,
				xdroot => $xdroot,
				editor => SVN::Delta::Editor->new (),
				targets => $arg{targets},
				unknown_verbose => 1,
				cb_unknown => sub {
				    $self->{checkout}->store ($_[1], { '.schedule' => 'add' });
				    print "A  $_[1]\n" unless $arg{quiet};
				},
			      );
    }
    else {
	$self->{checkout}->store ($arg{copath}, { '.schedule' => 'add' });
	print "A  $arg{copath}\n" unless $arg{quiet};
    }
}

sub do_delete {
    my ($self, %arg) = @_;
    my $xdroot = $self->xdroot (%arg);
    my @deleted;

    # check for if the file/dir is modified.
    $self->checkout_delta ( %arg,
			    baseroot => $xdroot,
			    xdroot => $xdroot,
			    absent_as_delete => 1,
			    delete_verbose => 1,
			    absent_verbose => 1,
			    editor => SVK::DeleteEditor->new
			    ( copath => $arg{copath},
			      dpath => $arg{path},
			      cb_delete => sub {
				  push @deleted, $_[1];
			      }
			    ),
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
	print "D  $_\n" unless $arg{quiet};
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
    my %values;

    my ($txn, $xdroot);
    my $entry = $self->{checkout}->get ($arg{copath});
    $entry->{'.schedule'} ||= '';
    $entry->{'.newprop'} ||= {};

    unless ($entry->{'.schedule'} eq 'add' || !$arg{repos}) {
	($txn, $xdroot) = create_xd_root ($self, %arg);

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

    $txn->abort if $txn;
}

sub do_revert {
    my ($self, %arg) = @_;

    my $xdroot = $self->xdroot (%arg);

    my $revert = sub {
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
	$self->{checkout}->store ($_[1],
				  {'.schedule' => undef});
	print loc("Reverted %1\n", $_[1]);
    };

    my $unschedule = sub {
	my $sche = $self->{checkout}->get ($_[1])->{'.schedule'};
	$self->{checkout}->store ($_[1],
				  {'.schedule' => undef,
				   '.newprop' => undef});
	-d $_[1] ? rmtree ([$_[1]]) : unlink($_[1])
	    if $sche eq 'add';
	print loc("Reverted %1\n", $_[1]);
    };

    my $revert_item = sub {
	exists $self->{checkout}->get ($_[1])->{'.schedule'} ?
	    &$unschedule (@_) : &$revert (@_);
    };

    if ($arg{recursive}) {
	$self->checkout_delta ( %arg,
				baseroot => $xdroot,
				xdroot => $xdroot,
				targets => $arg{targets},
				delete_verbose => 1,
				absent_verbose => 1,
				editor => SVK::RevertEditor->new
				( copath => $arg{copath},
				  dpath => $arg{path},
				  cb_revert => $revert,
				  cb_unschedule => $unschedule,
				),
			      );
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

    if ($arg{send_delta} && !$arg{add}) {
	my $txstream = SVN::TxDelta::new
	    ($arg{xdroot}->file_contents ($arg{path}), $arg{fh}, $arg{pool});

	SVN::TxDelta::send_txstream ($txstream, @$handle, $arg{pool});
    }
    else {
	SVN::TxDelta::send_stream ($arg{fh}, @$handle, $arg{pool})
    }
}

sub _delta_file {
    my ($self, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $rev = $arg{add} ? 0 : &{$arg{cb_rev}} ($arg{entry});
    my $cinfo = $arg{cinfo} || $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';

    if ($arg{cb_conflict} && $cinfo->{'.conflict'}) {
	&{$arg{cb_conflict}} ($arg{editor}, $arg{entry}, $arg{baton});
    }

    unless (-e $arg{copath}) {
	return if $schedule ne 'delete' && $arg{absent_ignore};
	if ($schedule eq 'delete' || $arg{absent_as_delete}) {
	    $arg{editor}->delete_entry ($arg{entry}, $rev, $arg{baton}, $pool);
	}
	else {
	    $arg{editor}->absent_file ($arg{entry}, $arg{baton}, $pool);
	}
	return;
    }

    my $fh = get_fh ($arg{xdroot}, '<', $arg{path}, $arg{copath});
    my $mymd5 = md5($fh);
    my $md5;

    return unless $schedule || $arg{add}
	|| $mymd5 ne ($md5 = $arg{xdroot}->file_md5_checksum ($arg{path}));

    my $baton = $arg{add} ?
	$arg{editor}->add_file ($arg{entry}, $arg{baton}, undef, -1, $pool) :
	$arg{editor}->open_file ($arg{entry}, $arg{baton}, $rev, $pool);

    my $newprop = $cinfo->{'.newprop'};
    $arg{editor}->change_file_prop ($baton, $_, $newprop->{$_}, $pool)
	for sort keys %$newprop;

    if ($arg{add} || $mymd5 ne ($md5 ||= $arg{xdroot}->file_md5_checksum ($arg{path}))) {
	seek $fh, 0, 0;
	$self->_delta_content (%arg, baton => $baton, fh => $fh, pool => $pool);
    }

    $arg{editor}->close_file ($baton, $mymd5, $pool);
}

sub _delta_dir {
    my ($self, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $rev = $arg{add} ? 0 : &{$arg{cb_rev}} ($arg{entry} || '');
    my $cinfo = $arg{cinfo} || $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';

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

    unless (-d $arg{copath}) {
	if ($schedule ne 'delete') {
	    return if $arg{absent_ignore};
	    if ($arg{absent_as_delete}) {
		$arg{editor}->delete_entry ($arg{entry}, $rev, $arg{baton}, $pool);
	    }
	    else {
		$arg{editor}->absent_directory ($arg{entry}, $arg{baton}, $pool);
	    }
	    return unless $arg{absent_verbose};
	}
    }

    my ($entries, $baton) = ({});
    if ($schedule eq 'delete') {
	# XXX: limit with targets
	# XXX: should still be recursion since the entries
	# might not be consistent
	$arg{editor}->delete_entry ($arg{entry}, $rev, $arg{baton}, $pool);
	if ($arg{delete_verbose}) {
	    for ($self->{checkout}->find
		 ($arg{copath}, {'.schedule' => 'delete'})) {
		s|^$arg{copath}/?||;
		$arg{editor}->delete_entry ("$arg{entry}/$_", $rev, $arg{baton}, $pool)
		    if $_;
	    }
	}
	return;
    }
    elsif ($arg{add}) {
	$baton = $arg{root} ? $arg{baton} :
	    $arg{editor}->add_directory ($arg{entry}, $arg{baton}, undef, -1, $pool);
    }
    else {
	$entries = $arg{xdroot}->dir_entries ($arg{path})
	    if $arg{kind} == $SVN::Node::dir;
	$baton = $arg{root} ? $arg{baton} : $arg{editor}->open_directory ($arg{entry}, $arg{baton}, $rev, $pool);
    }

    if ($schedule eq 'prop' || $arg{add}) {
	my $newprop = $cinfo->{'.newprop'};
	$arg{editor}->change_dir_prop ($baton, $_, $newprop->{$_}, $pool)
	    for sort keys %$newprop;
    }

    for (sort keys %{$entries}) {
	my $kind = $entries->{$_}->kind;
	my $delta = ($kind == $SVN::Node::file) ? \&_delta_file : \&_delta_dir;
	$self->$delta ( %arg,
		   entry => $arg{entry} ? "$arg{entry}/$_" : $_,
		   kind => $kind,
		   targets => $targets->{$_},
		   baton => $baton,
		   root => 0,
		   cinfo => undef,
		   path => "$arg{path}/$_",
		   copath => "$arg{copath}/$_")
	    if !defined $arg{targets} || exists $targets->{$_};
    }

    # check scheduled addition
    opendir my ($dir), $arg{copath};

    if ($dir) {

    my $svn_ignore = $self->get_props ($arg{xdroot}, $arg{path},
				       $arg{copath})->{'svn:ignore'}
        if $arg{kind} == $SVN::Node::dir;
    my $ignore = ignore (split ("\n", $svn_ignore || ''));
    for (grep { !m/^\.+$/ && !exists $entries->{$_} } readdir ($dir)) {
	next if m/$ignore/;
	my $ccinfo = $self->{checkout}->get ("$arg{copath}/$_");
	my $sche = $ccinfo->{'.schedule'} || '';
	unless ($sche || ($arg{auto_add} && $arg{add})) {
	    if ($arg{cb_unknown} &&
		(!defined $arg{targets} || exists $targets->{$_})) {
		if ($arg{unknown_verbose}) {
		    my $newco = "$arg{copath}/$_";
		    find (sub {
			      return if m/$ignore/;
			      my $dpath = $File::Find::name;
			      $dpath =~ s/^$arg{copath}/$arg{path}/;
			      &{$arg{cb_unknown}} ($dpath, $File::Find::name);
			  },
			  $targets->{$_} ? map {"$newco/$_"} @{$targets->{$_}}
			                : $newco);
		}
		else {
		    &{$arg{cb_unknown}} ("$arg{path}/$_", "$arg{copath}/$_")
			if $arg{cb_unknown};
		}

	    }
	    next;
	}
	my $delta = (-d "$arg{copath}/$_") ? \&_delta_dir : \&_delta_file;
	$self->$delta ( %arg,
		   add => 1,
		   entry => $arg{entry} ? "$arg{entry}/$_" : $_,
		   kind => $SVN::Node::none,
		   baton => $baton,
		   targets => $targets->{$_},
		   root => 0,
		   path => "$arg{path}/$_",
		   cinfo => $ccinfo,
		   copath => "$arg{copath}/$_")
	    if !defined $arg{targets} || exists $targets->{$_};

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
    my $kind = $arg{xdroot}->check_path ($arg{path});
    my $copath = $arg{copath};
    $arg{editor} = SVK::DelayEditor->new ($arg{editor})
	unless $arg{nodelay};
    $arg{editor} = SVN::Delta::Editor->new (_debug => 1, _editor => [$arg{editor}])
	if $arg{debug};
    $arg{cb_rev} ||= sub { my $target = shift;
			   $target = $target ? "$copath/$target" : $copath;
			   $self->_get_rev ($target);
		       };
    $arg{kind} = $kind;
    my $rev = &{$arg{cb_rev}} ('');
    my $baton = $arg{editor}->open_root ($rev);

    if ($kind == $SVN::Node::file) {
	$self->_delta_file (%arg, baton => $baton);
    }
    elsif ($kind == $SVN::Node::dir) {
	$self->_delta_dir (%arg, baton => $baton, root => 1);
    }
    else {
	my $delta = (-d $arg{copath}) ? \&_delta_dir : \&_delta_file;
	my $sche =
	    $self->{checkout}->get ($arg{copath})->{'.schedule'} || '';

	if ($sche eq 'add') {
	    $self->$delta ( %arg,
		       add => 1,
		       baton => $baton,
		       root => 1);
	}
	else {
	    if ($arg{unknown_verbose}) {
		find (sub {
#			  return if m/$ignore/;
			  my $dpath = $File::Find::name;
			  $dpath =~ s/^$arg{copath}/$arg{path}/;
			  &{$arg{cb_unknown}} ($dpath, $File::Find::name);
		      },
		      $arg{targets} ? map {"$arg{copath}/$_"} @{$arg{targets}}
		      : $arg{copath});
	    }
	    else {
		&{$arg{cb_unknown}} ($arg{path}, $arg{copath})
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

    my $editor = SVN::Delta::Editor->new
	( SVN::Repos::get_commit_editor
	  ( $arg{repos},
	    "file://$arg{repospath}",
	    $arg{path}, $ENV{USER},
	    $arg{message},
	    sub { print loc("Directory %1 imported to depotpath %2 as revision %3.\n", $arg{copath}, $arg{depotpath}, $_[0]) }));

    $editor = SVK::XD::CheckEditor->new ($editor)
	if $arg{check_only};

    my $baton = $editor->open_root ($yrev);

    if (exists $self->{checkout}->get ($arg{copath})->{depotpath}) {
	die loc("Import source cannot be a checkout path");
    }

    # XXX: check the entry first
    $self->{checkout}->store ($arg{copath},
			      {depotpath => $arg{depotpath},
			       '.newprop' => undef,
			       '.conflict' => undef,
			       revision =>0});

    $self->_delta_dir (%arg,
		add => 1,
	        auto_add => 1,
		cb_rev => sub { $yrev },
		editor => $editor,
		baseroot => $root,
		xdroot => $root,
		kind => $SVN::Node::dir,
		absent_as_delete => 1,
		baton => $baton, root => 1);


    $editor->close_directory ($baton);

    $editor->close_edit ();

    $self->{checkout}->store ($arg{copath},
			      {depotpath => undef,
			       revision => undef,
			       '.schedule' => undef});


}

sub get_keyword_layer {
    my ($root, $path) = @_;
    my $pool = SVN::Pool->new_default;
    my $k = eval { $root->node_prop ($path, 'svn:keywords') };
    undef $@;
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
         sub { $_[1] =~ s/\$($keyword)\b[-#:\w\t \.\/]*\$/"\$$1: ".&{$kmap{$1}}($root, $path).' $'/eg },
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

package SVK::XD::CheckEditor;
use SVK::I18N;
our @ISA = qw(SVN::Delta::Editor);

sub close_edit {
    my $self = shift;
    print loc("Commit checking finished.\n");
    print loc("%*(%1,conflict) found.\n", $self->{conflicts}) if $self->{conflicts};
    $self->{_editor}->abort_edit (@_);
}

sub abort_edit {
    my $self = shift;
    print loc("Empty merge.\n");
    $self->{_editor}->abort_edit (@_);
}

package SVK::XD::Editor;
use SVK::I18N;
require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);
use File::Path;
use SVK::Util qw( get_anchor md5 );

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
}

sub open_root {
    my ($self, $base_revision) = @_;
    $self->{baserev} = $base_revision;
    return '';
}

sub add_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 already exists", $path) if -e $copath;
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 does not exist", $path) unless -e $copath;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    my $base;
    return if $self->{check_only};
    my $copath = $path;
    $self->{get_copath}($copath);
    if (-e $copath) {
	my ($dir,$file) = get_anchor (1, $copath);
	my $basename = "$dir.svk.$file.base";
	$base = SVK::XD::get_fh ($self->{oldroot}, '<',
				 "$self->{anchor}/$path", $copath);
	if ($checksum) {
	    my $md5 = md5($base);
	    use Carp;
	    confess "bzz";
	    die loc("source checksum mismatch") if $md5 ne $checksum;
	    seek $base, 0, 0;
	}
	rename ($copath, $basename);
	$self->{base}{$path} = [$base, $basename];
    }
    my $fh = SVK::XD::get_fh ($self->{newroot}, '>',
			      "$self->{anchor}/$path", $copath)
	or warn "can't open $path";

    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty($pool),
				 $fh, undef, undef, $pool)];
}

sub close_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    if ($self->{base}{$path}) {
	close $self->{base}{$path}[0];
	unlink $self->{base}{$path}[1];
	delete $self->{base}{$path};
    }
    elsif (!$self->{update} && !$self->{check_only}) {
	$self->{xd}->do_add (copath => $copath, quiet => 1);
    }
    $self->{checkout}->store ($copath, {revision => $self->{revision}})
	if $self->{update};
    chmod 0755, $copath
	if $self->{exe}{$path};
}

sub add_directory {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    mkdir ($copath) unless $self->{check_only};
    $self->{xd}->do_add (copath => $copath, quiet => 1)
	if !$self->{update} && !$self->{check_only};
    return $path;
}

sub open_directory {
    my ($self, $path) = @_;
    # XXX: test if directory exists
    return $path;
}

sub delete_entry {
    my ($self, $path, $revision) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    # XXX: check if everyone under $path is sane for delete";
    return if $self->{check_only};
    if ($self->{update}) {
	-d $copath ? rmtree ([$copath]) : unlink($copath);
    }
    else {
	$self->{xd}->do_delete (%$self,
				path => "$self->{anchor}/$path",
				copath => $copath,
				quiet => 1);
    }
}

sub close_directory {
    my ($self, $path) = @_;
    my $copath = $path;
    eval {$self->{get_copath}($copath)};
    undef $@, return if $@;
    $self->{checkout}->store_recursively ($copath,
					  {revision => $self->{revision},
					   '.deleted' => undef})
	if $self->{update};
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    return if $self->{check_only};
    my $copath = $path;
    $self->{get_copath}($copath);
    # XXX: do executable unset also.
    $self->{exe}{$path}++
	if $name eq 'svn:executable' && defined $value;
    $self->{xd}->do_propset ( quiet => 1,
			      copath => $copath,
			      propname => $name,
			      propvalue => $value,
			    )
	unless $self->{update};
}

sub change_dir_prop {
    my ($self, @arg) = @_;
    $self->change_file_prop (@arg);
}

sub close_edit {
    my ($self) = @_;
    $self->close_directory('');
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
