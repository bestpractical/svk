package SVK::XD;
use strict;
our $VERSION = '0.09';
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
require SVN::Delta;
require SVK::MergeEditor;
use SVK::RevertEditor;
use SVK::DeleteEditor;
use Data::Hierarchy;
use File::Spec;
use File::Find;
use File::Path;
use YAML;
use File::Temp qw/:mktemp/;
use PerlIO::via::dynamic;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}

sub get_anchor {
    my $needtarget = shift;
    map {
	my (undef,$anchor,$target) = File::Spec->splitpath ($_);
	chop $anchor if length ($anchor) > 1;
	($anchor, $needtarget ? ($target) : ())
    } @_;
}

sub condense {
    my $info = shift;
    my @targets = map {Cwd::abs_path ($_ || '')} @_;
    my ($anchor, $report);
    $report = $_[0];
    for (@targets) {
	if (!$anchor) {
	    $anchor = $_;
	    $report = $_[0]
	}
	my $schedule = $info->{checkout}->get_single ($anchor)->{schedule} || '';
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

sub create_xd_root {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my ($txn, $root);

    my @paths = $info->{checkout}->find ($arg{copath}, {revision => qr'.*'});

    return (undef, $fs->revision_root
	    ($info->{checkout}->get ($paths[0] || $arg{copath})->{revision}))
	if $#paths <= 0;

    for (@paths) {
	my $rev = $info->{checkout}->get ($_)->{revision};
	my $deleted = $info->{checkout}->get ($_)->{deleted};
	unless ($root) {
	    $txn = $fs->begin_txn ($rev);
	    $root = $txn->root();
	    next if $_ eq $arg{copath};
	}
	s|^$arg{copath}/||;
	$root->make_dir ($arg{path})
	    if $root->check_path ($arg{path}) == $SVN::Node::none;
	if ($deleted) {
	    $root->delete ("$arg{path}/$_");
	}
	else {
	    SVN::Fs::revision_link ($fs->revision_root ($rev),
				    $root, "$arg{path}/$_");
	}
    }
    return ($txn, $root);
}

sub translator {
    my ($target) = @_;
    $target .= '/' if $target;
    $target ||= '';
    return qr/^$target/;
}

sub xd_storage_cb {
    my ($info, %arg) = @_;
    my $t = translator ($arg{target});

    # translate to abs path before any check
    return
	( cb_exist => sub { $_ = shift; s|$t|$arg{copath}/|; -e $_},
	  cb_rev => sub { $_ = shift; s|$t|$arg{copath}/|;
			  $info->{checkout}->get ($_)->{revision} },
	  cb_conflict => sub { $_ = shift; s|$t|$arg{copath}/|;
			       $info->{checkout}->store ($_, {conflict => 1})
				   unless $arg{check_only};
			   },
	  cb_localmod => sub { my ($path, $checksum) = @_;
			       $_ = $path; s|$t|$arg{copath}/|;
			       my $base = get_fh ($arg{oldroot}, '<',
						  "$arg{anchor}/$arg{path}", $_);
			       my $md5 = SVK::MergeEditor::md5 ($base);
			       return undef if $md5 eq $checksum;
			       seek $base, 0, 0;
			       return [$base, undef, $md5];
			   });
}

sub get_editor {
    my ($info, %arg) = @_;

    my $storage = SVK::XD::Editor->new
	( %arg,
	  get_copath => sub { my $t = translator($arg{target});
			      $_[0] = $arg{copath}, return
				  if $arg{target} eq $_[0];
			      $_[0] =~ s|$t|$arg{copath}/|
				  or die "unable to translate $_[0] with $t";
			      $_[0] =~ s|/$||;
			  },
	  checkout => $info->{checkout},
	  info => $info,
	);

    return $storage unless wantarray;

    return ($storage, xd_storage_cb ($info, %arg));
}

sub do_update {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;

    my ($txn, $xdroot) = create_xd_root ($info, %arg);
    my ($anchor, $target) = ($arg{path}, '');
    $arg{target_path} ||= $arg{path};
    my ($tanchor, $ttarget) = ($arg{target_path}, '');

    print "syncing $arg{depotpath}($arg{path}) to $arg{copath} to $arg{rev}\n";
    unless ($xdroot->check_path ($arg{path}) == $SVN::Node::dir) {
	($anchor, $target, $tanchor, $ttarget) = 
	    get_anchor (1, $arg{path}, $arg{target_path});
    }

    my $newroot = $fs->revision_root ($arg{rev});
    my ($storage, %cb) = get_editor ($info, %arg,
				     oldroot => $xdroot,
				     newroot => $newroot,
				     anchor => $anchor,
				     target => $target,
				     update => 1);

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


    SVN::Repos::dir_delta ($xdroot, $anchor, $target,
			   $newroot, $arg{target_path},
			   $editor, undef,
			   1, 1, 0, 1);

    $txn->abort if $txn;
}

sub do_add {
    my ($info, %arg) = @_;

    if ($arg{recursive}) {
	my ($txn, $xdroot) = SVK::XD::create_xd_root ($info, %arg);
	SVK::XD::checkout_delta ($info,
				 %arg,
				 baseroot => $xdroot,
				 xdroot => $xdroot,
				 editor => SVN::Delta::Editor->new (),
				 targets => $arg{targets},
				 unknown_verbose => 1,
				 strict_add => 1,
				 cb_unknown => sub {
				     $info->{checkout}->store ($_[1], { schedule => 'add' });
				     print "A  $_[1]\n" unless $arg{quiet};
				 },
			    );
	$txn->abort if $txn;
    }
    else {
	$info->{checkout}->store ($arg{copath}, { schedule => 'add' });
	print "A  $arg{copath}\n" unless $arg{quiet};
    }
}

sub do_delete {
    my ($info, %arg) = @_;
    my ($txn, $xdroot) = SVK::XD::create_xd_root ($info, %arg);
    my @deleted;

    # check for if the file/dir is modified.
    SVK::XD::checkout_delta ($info,
			     %arg,
			     baseroot => $xdroot,
			     xdroot => $xdroot,
			     absent_as_delete => 1,
			     delete_verbose => 1,
			     absent_verbose => 1,
			     strict_add => 1,
			     editor => SVK::DeleteEditor->new
			     (copath => $arg{copath},
			      dpath => $arg{path},
			      cb_delete => sub {
				  push @deleted, $_[1];
			      }
			     ),
			     cb_unknown => sub {
				 die "$_[0] is not under version control";
			     }
			    );

    $txn->abort if $txn;

    # actually remove it from checkout path
    my @paths = grep {-e $_} ($arg{targets} ?
			      map { "$arg{copath}/$_" } @{$arg{targets}}
			      : $arg{copath});
    find(sub {
	     my $cpath = $File::Find::name;
	     no warnings 'uninitialized';
	     return if $info->{checkout}->get_single ($cpath)->{schedule}
		 eq 'delete';
	     push @deleted, $cpath;
	 }, @paths) if @paths;

    for (@deleted) {
	print "D  $_\n";
	$info->{checkout}->store ($_, {schedule => 'delete'});
    }

    rmtree (\@paths) if @paths;
}

sub do_proplist {
    my ($info, %arg) = @_;

    my ($txn, $xdroot);
    my $props = {};

    if ($arg{rev}) {
	$xdroot = $arg{repos}->fs->revision_root ($arg{rev});
    }
    else {
	($txn, $xdroot) = create_xd_root ($info, %arg);
    }

    $props = get_props ($info, $xdroot, $arg{path},
			$arg{rev} ? undef : $arg{copath})
	if $xdroot;

    $txn->abort if $txn;

    return $props;
}

sub do_propset_direct {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);
    my $kind = $root->check_path ($arg{path});

    die "path $arg{path} does not exist" if $kind == $SVN::Node::none;

    my $edit = get_commit_editor ($root,
				  sub { print "Committed revision $_[0].\n" },
				  '/', %arg);
    $edit->open_root();

    if ($kind == $SVN::Node::dir) {
	$edit->change_dir_prop ($arg{path}, $arg{propname}, $arg{propvalue});
    }
    else {
	$edit->change_file_prop ($arg{path}, $arg{propname}, $arg{propvalue});
    }

    $edit->close_edit();
}

sub do_propset {
    my ($info, %arg) = @_;
    my %values;

    my ($txn, $xdroot);
    my $entry = $info->{checkout}->get_single ($arg{copath});
    $entry->{schedule} ||= '';
    $entry->{newprop} ||= {};

    unless ($entry->{schedule} eq 'add' || !$arg{repos}) {
	($txn, $xdroot) = create_xd_root ($info, %arg);

	die "$arg{copath} ($arg{path})not under version control"
	    if $xdroot->check_path ($arg{path}) == $SVN::Node::none;
    }

    #XXX: support working on multiple paths and recursive
    die "$arg{copath} is already scheduled for delete"
	if $entry->{schedule} eq 'delete';
    %values = %{$entry->{newprop}}
	if exists $entry->{schedule};
    $info->{checkout}->store ($arg{copath},
			      { schedule => $entry->{schedule} || 'prop',
				newprop => {%values,
					    $arg{propname} =>
					    $arg{propvalue},
					   }});
    print " M $arg{copath}\n" unless $arg{quiet};

    $txn->abort if $txn;
}

sub do_revert {
    my ($info, %arg) = @_;

    my ($txn, $xdroot) = SVK::XD::create_xd_root ($info, %arg);

    my $revert = sub {
	my $kind = $xdroot->check_path ($_[0]);
	if ($kind == $SVN::Node::none) {
	    print "$_[1] is not versioned, ignored\n";
	    return;
	}
	if ($kind == $SVN::Node::dir) {
	    mkdir $_[1] unless -e $_[1];
	}
	else {
	    my $fh = get_fh ($xdroot, '>', $_[0], $_[1]);
	    my $content = $xdroot->file_contents ($_[0]);
	    local $/ = \16384;
	    while (<$content>) {
		print $fh $_;
	    }
	    close $fh;
	}
	$info->{checkout}->store ($_[1],
				  {schedule => undef});
	print "Reverted $_[1]\n";
    };

    my $unschedule = sub {
	$info->{checkout}->store ($_[1],
				  {schedule => undef,
				   newprop => undef});
	print "Reverted $_[1]\n";
    };

    my $revert_item = sub {
	exists $info->{checkout}->get ($_[1])->{schedule} ?
	    &$unschedule (@_) : &$revert (@_);
    };

    if ($arg{recursive}) {
	SVK::XD::checkout_delta ($info,
				 %arg,
				 baseroot => $xdroot,
				 xdroot => $xdroot,
				 targets => $arg{targets},
				 delete_verbose => 1,
				 absent_verbose => 1,
				 strict_add => 1,
				 editor => SVK::RevertEditor->new
				 (copath => $arg{copath},
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

    $txn->abort if $txn;

}

use Regexp::Shellish qw( :all ) ;

sub ignore {
    no warnings;
    my @ignore = qw/*.o #*# .#* *.lo *.la .*.rej *.rej .*~ *~ .DS_Store
		    svk-commit*.tmp/;

    return join('|', map {compile_shellish $_} (@ignore, @_));
}

sub _delta_content {
    my ($info, %arg) = @_;

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
    my ($info, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $rev = $arg{add} ? 0 : &{$arg{cb_rev}} ($arg{entry});
    my $schedule = $info->{checkout}->get_single ($arg{copath})->{schedule} || '';

    if ($arg{cb_conflict} && $info->{checkout}->get_single ($arg{copath})->{conflict}) {
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
    my $mymd5 = SVK::MergeEditor::md5($fh);

    return unless $schedule || $arg{add}
	|| $mymd5 ne $arg{xdroot}->file_md5_checksum ($arg{path});

    my $baton = $arg{add} ?
	$arg{editor}->add_file ($arg{entry}, $arg{baton}, undef, -1, $pool) :
	$arg{editor}->open_file ($arg{entry}, $arg{baton}, $rev, $pool);

    my $newprop = $info->{checkout}->get_single ($arg{copath})->{newprop};
    $arg{editor}->change_file_prop ($baton, $_, $newprop->{$_}, $pool)
	for keys %$newprop;

    if ($arg{add} || $mymd5 ne $arg{xdroot}->file_md5_checksum ($arg{path})) {
	seek $fh, 0, 0;
	_delta_content ($info, %arg, baton => $baton, fh => $fh, pool => $pool);
    }

    $arg{editor}->close_file ($baton, $mymd5, $pool);
}

sub _delta_dir {
    my ($info, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $rev = $arg{add} ? 0 : &{$arg{cb_rev}} ($arg{entry} || '');
    my $schedule = $info->{checkout}->get_single ($arg{copath})->{schedule} || '';

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
	    for ($info->{checkout}->find
		 ($arg{copath}, {schedule => 'delete'})) {
		s|^$arg{copath}/?||;
		$arg{editor}->delete_entry ("$arg{entry}/$_", $rev, $arg{baton}, $pool)
		    if $_;
	    }
	}
	return;
    }
    elsif ($arg{add}) {
	$baton =
	    $arg{editor}->add_directory ($arg{entry}, $arg{baton}, undef, -1, $pool);
    }
    else {
	$entries = $arg{xdroot}->dir_entries ($arg{path})
	    if $arg{kind} == $SVN::Node::dir;
	$baton = $arg{root} ? $arg{baton} : $arg{editor}->open_directory ($arg{entry}, $arg{baton}, $rev, $pool);
    }

    if ($schedule eq 'prop' || $schedule eq 'add') {
	my $newprop = $info->{checkout}->get_single ($arg{copath})->{newprop};
	$arg{editor}->change_dir_prop ($baton, $_, $newprop->{$_}, $pool)
	    for keys %$newprop;
    }

    for (keys %{$entries}) {
	my $kind = $entries->{$_}->kind;
	my $delta = ($kind == $SVN::Node::file) ? \&_delta_file : \&_delta_dir;
	&{$delta} ($info, %arg,
		   entry => $arg{entry} ? "$arg{entry}/$_" : $_,
		   kind => $kind,
		   targets => $targets->{$_},
		   baton => $baton,
		   root => 0,
		   path => "$arg{path}/$_",
		   copath => "$arg{copath}/$_")
	    if !defined $arg{targets} || exists $targets->{$_};

    }
    # check scheduled addition
    opendir my ($dir), $arg{copath};

    if ($dir) {

    my $svn_ignore = get_props ($info, $arg{xdroot}, $arg{path},
				$arg{copath})->{'svn:ignore'}
        if $arg{kind} == $SVN::Node::dir;
    my $ignore = ignore (split ("\n", $svn_ignore || ''));
    for (grep { !m/^\.+$/ && !exists $entries->{$_} } readdir ($dir)) {
	next if m/$ignore/;
	my $sche = $arg{strict_add} ?
	    $info->{checkout}->get_single ("$arg{copath}/$_")->{schedule} :
	    $info->{checkout}->get ("$arg{copath}/$_")->{schedule};
	unless ($sche) {
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
	&{$delta} ($info, %arg,
		   add => 1,
		   entry => $arg{entry} ? "$arg{entry}/$_" : $_,
		   kind => $arg{xdroot}->check_path ("$arg{path}/$_"),
		   baton => $baton,
		   targets => $targets->{$_},
		   root => 0,
		   path => "$arg{path}/$_",
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
    my ($info, $path) = @_;
    $info->{checkout}->get($path)->{revision}
}


# options:
#  delete_verbose: generate delete_entry calls for subdir within deleted entry
#  absent_verbose: generate absent_* calls for subdir within absent entry
#  unknown_verbose: generate cb_unknown calls for subdir within absent entry
#  absent_ignore: don't generate absent_* calls.
#  strict_add: add schedule must be on the entry check, not any parent.

sub checkout_delta {
    my ($info, %arg) = @_;

    my $kind = $arg{xdroot}->check_path ($arg{path});
    $arg{cb_rev} ||= sub { my $target = shift;
			   $target = $target ? "$arg{copath}/$target" : $arg{copath};
			   _get_rev($info, $target);
		       };
    $arg{kind} = $kind;
    my $rev = &{$arg{cb_rev}} ('');
    my $baton = $arg{editor}->open_root ($rev);

    if ($kind == $SVN::Node::file) {
	_delta_file ($info, %arg, baton => $baton);
    }
    elsif ($kind == $SVN::Node::dir) {
	_delta_dir ($info, %arg, baton => $baton, root => 1);
    }
    else {
	my $delta = (-d $arg{copath}) ? \&_delta_dir : \&_delta_file;
	my $sche = ($arg{strict_add} ?
	    $info->{checkout}->get_single ($arg{copath})->{schedule} :
	    $info->{checkout}->get ($arg{copath})->{schedule}) || '';

	if ($sche eq 'add') {
	    &{$delta} ($info, %arg,
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
    my ($info, $entry) = @_;
    my $val = $info->{checkout}->get_single ($entry);
    return unless $val && $val->{conflict};
    $info->{checkout}->store ($entry, {%$val, conflict => undef});
    print "$entry marked as resolved.\n";
}

sub do_resolved {
    my ($info, %arg) = @_;

    if ($arg{recursive}) {
	for ($info->{checkout}->find ($arg{copath}, {conflict => 1})) {
	    resolved_entry ($info, $_);
	}
    }
    else {
	resolved_entry ($info, $arg{copath});
    }
}

sub do_import {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my $root = $fs->revision_root ($yrev);
    my $kind = $root->check_path ($arg{path});

    die "import destination is a file"
	if $kind == $SVN::Node::file;

    if ($kind == $SVN::Node::none) {
	my $edit = SVN::Simple::Edit->new
	    (_editor => [SVN::Repos::get_commit_editor($arg{repos},
					    "file://$arg{repospath}",
					    '/', $ENV{USER},
					    "directory for svk import",
					    sub {print "Import path $arg{path} initialized.\n"})],
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
	    sub {print "Directory $arg{copath} imported to depotpath $arg{depotpath} as revision $_[0].\n"}));

    $editor = SVK::XD::CheckEditor->new ($editor)
	if $arg{check_only};

    my $baton = $editor->open_root ($yrev);

    if (exists $info->{checkout}->get ($arg{copath})->{depotpath}) {
	die "Import source is a checkout path. it's likely not what you want";
    }

    # XXX: check the entry first
    $info->{checkout}->store ($arg{copath},
			      {depotpath => $arg{depotpath},
			       schedule => 'add',
			       newprop => undef,
			       conflict => undef,
			       revision =>0});

    _delta_dir ($info, %arg,
		cb_rev => sub { $yrev },
		editor => $editor,
		baseroot => $root,
		xdroot => $root,
		kind => $SVN::Node::dir,
		absent_as_delete => 1,
		baton => $baton, root => 1);


    $editor->close_directory ($baton);

    $editor->close_edit ();

    $info->{checkout}->store ($arg{copath},
			      {depotpath => undef,
			       revision => undef,
			       schedule => undef});


}

use SVN::Simple::Edit;

sub get_commit_editor {
    my ($xdroot, $committed, $path, %arg) = @_;
    ${$arg{callback}} = $committed if $arg{editor};
    return SVN::Simple::Edit->new
	(_editor => [$arg{editor} ||
		     SVN::Repos::get_commit_editor($arg{repos},
						   "file://$arg{repospath}",
						   $path,
						   $arg{author}, $arg{message},
						   $committed)],
	 base_path => $path,
	 $arg{mirror} ? () : ( root => $xdroot ),
	 missing_handler =>
	 SVN::Simple::Edit::check_missing ($xdroot));
}

sub do_copy_direct {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $edit = get_commit_editor ($fs->revision_root ($fs->youngest_rev),
				  sub { print "Committed revision $_[0].\n" },
				  '/', %arg);
    # XXX: check parent, check isfile, check everything...
    $edit->open_root();
    $edit->copy_directory ($arg{dpath}, "file://$arg{repospath}$arg{path}",
			   $arg{rev});
    $edit->close_edit();
}

sub get_keyword_layer {
    my ($root, $path) = @_;
    my $pool = SVN::Pool->new_default;
    return if $root->check_path ($path) == $SVN::Node::none;
    my $k = eval { $root->node_prop ($path, 'svn:keywords') };
    use Carp;
    confess "can't get keyword layer for $path: $@" if $@;

    return undef unless $k;

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

#    use Carp qw/cluck/;
#    cluck "======> has keyword";

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
    my ($info, $root, $path, $copath) = @_;

    my ($props, $entry) = ({});

    $entry = $info->{checkout}->get_single ($copath) if $copath;
    $entry->{newprop} ||= {};
    $entry->{schedule} ||= '';

    unless ($entry->{schedule} eq 'add') {

	die "$path not found"
	    if $root->check_path ($path) == $SVN::Node::none;
	$props = $root->node_proplist ($path);
    }

    return {%$props,
	    %{$entry->{newprop}}};


}

sub md5file {
    my $fname = shift;
    open my $fh, '<', $fname;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

package SVK::XD::CheckEditor;
our @ISA = qw(SVN::Delta::Editor);

sub close_edit {
    my $self = shift;
    print "Commit checking finished.\n";
    print $self->{conflicts}." Conflicts found.\n" if $self->{conflicts};
    $self->{_editor}->abort_edit (@_);
}

sub abort_edit {
    my $self = shift;
    print "Empty merge.\n";
    $self->{_editor}->abort_edit (@_);
}

package SVK::XD::Editor;
require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);
use File::Path;

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
    die "$path already exists" if -e $copath;
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die "path not exists" unless -e $copath;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    my $base;
    return if $self->{check_only};
    my $copath = $path;
    $self->{get_copath}($copath);
    if (-e $copath) {
	my ($dir,$file) = SVK::XD::get_anchor (1, $copath);
	my $basename = "$dir.svk.$file.base";
	$base = SVK::XD::get_fh ($self->{oldroot}, '<',
				 "$self->{anchor}/$path", $copath);
	if ($checksum) {
	    my $md5 = SVK::MergeEditor::md5($base);
	    die "source checksum mismatch" if $md5 ne $checksum;
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
	SVK::XD::do_add ($self->{info}, copath => $copath, quiet => 1);
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
    mkdir ($copath);
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
    -d $copath ? rmtree ([$copath]) : unlink($copath);
}

sub close_directory {
    my ($self, $path) = @_;
    my $copath = $path;
    eval {$self->{get_copath}($copath)};
    return if $@;
    $self->{checkout}->store_recursively ($copath,
					  {revision => $self->{revision},
					   deleted => undef})
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
    SVK::XD::do_propset ($self->{info},
			 quiet => 1,
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

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
