package SVN::XD;
use strict;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
require SVN::Delta;
use Data::Hierarchy;
use File::Spec;
use File::Path;
use YAML;
use Algorithm::Merge;
use File::Temp qw/:mktemp/;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}

sub create_xd_root {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my ($txn, $root);

    my @paths = $info->{checkout}->find ($arg{copath}, {revision => qr'.*'});

    return (undef, $fs->revision_root
	    ($info->{checkout}->get ($arg{copath})->{revision}))
	if $#paths <= 0;

    for (@paths) {
	my $rev = $info->{checkout}->get ($_)->{revision};
	if ($_ eq $arg{copath}) {
	    $txn = $fs->begin_txn ($rev);
	    $root = $txn->root();
	    next;
	}
	s|^$arg{copath}/||;
	$root->make_dir ($arg{path})
	    if $root->check_path ($arg{path}) == $SVN::Node::none;
	SVN::Fs::revision_link ($fs->revision_root ($rev),
				$root, "$arg{path}/$_");
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
    my ($info, $anchor, $target, $copath, $xdroot) = @_;
    my $t = translator ($target, $copath);

    return
	( cb_exist => sub { $_ = shift; s|$t|$copath/|; -e $_},
	  cb_rev => sub { $_ = shift; s|$t|$copath/|;
			  $info->{checkout}->get ($_)->{revision} },
	  cb_conflict => sub { $_ = shift; s|$t|$copath/|;
			       $info->{checkout}->store ($_, {conflict => 1})},
	  cb_localmod => sub { my ($path, $checksum) = @_;
			       $_ = $path; s|$t|$copath/|;
			       my $base = get_fh ($xdroot, '<',
						  "$anchor/$path", $_);
			       my $md5 = SVN::XD::MergeEditor::md5 ($base);
			       return undef if $md5 eq $checksum;
			       seek $base, 0, 0;
			       return [$base, $_, $md5];
			   });
}

sub do_update {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;

    my ($txn, $xdroot) = create_xd_root ($info, %arg);
    my ($anchor, $target, $copath) = ($arg{path});

    print "syncing $arg{depotpath}($arg{path}) to $arg{copath} to $arg{rev}\n";
    unless ($xdroot->check_path ($arg{path}) == $SVN::Node::dir) {
	(undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
	undef $target unless $target;
	chop $anchor if length($anchor) > 1;

	(undef,undef,$copath) = File::Spec->splitpath ($arg{copath});
    }

    my $storage = SVN::XD::Editor->new
	( copath => $arg{copath},
	  get_copath => sub { my $t = translator($target);
			      $_[0] = $arg{copath}, return
				  if $target && $target eq $_[0];
			      $_[0] =~ s|$t|$arg{copath}/|
				  or die "unable to translate $_[0] with $t" },
	  oldroot => $xdroot,
	  newroot => $fs->revision_root ($arg{rev}),
	  anchor => $anchor,
	  checkout => $info->{checkout},
	  info => $info,
	  update => 1,
	);

    my $editor = SVN::XD::MergeEditor->new
	(_debug => 0,
	 fs => $fs,
	 anchor => $anchor,
	 base_anchor => $anchor,
	 base_root => $xdroot,
	 target => $target,
	 storage => $storage,
	 xd_storage_cb ($info, $anchor, $target, $arg{copath}, $xdroot),
	);

#    $editor = SVN::Delta::Editor->new(_debug=>1),

    SVN::Repos::dir_delta ($xdroot, $anchor, $target,
			   $fs->revision_root ($arg{rev}), $arg{path},
			   $editor, undef,
			   1, 1, 0, 1);

    $txn->abort if $txn;
}

sub do_add {
    my ($info, %arg) = @_;

    if ($arg{recursive}) {
	find(sub {
		 my $cpath = $File::Find::name;
		 # do dectation also
		 $info->{checkout}->store ($cpath, { schedule => 'add' });
		 print "A  $cpath\n";
	     }, $arg{copath})
    }
    else {
	$info->{checkout}->store ($arg{copath}, { schedule => 'add' });
	print "A  $arg{copath}\n" unless $arg{quiet};
    }
}

sub do_delete {
    my ($info, %arg) = @_;

    # check for if the file/dir is modified.
    checkout_crawler ($info,
		      (%arg,
		       cb_unknown =>
		       sub { die "$_[1] is not under version control" },
		       cb_add =>
		       sub {
			   die "$_[1] scheduled for add, use revert instead";
		       },
		       cb_changed =>
		       sub {
			   die "$_[1] changed";
		       },
		      )
		     );

    # actually remove it from checkout path
    find(sub {
	     my $cpath = $File::Find::name;
	     print "D  $cpath\n";
	     $info->{checkout}->store ($cpath, {schedule => 'delete'});
	 },
	 $arg{copath});

    -d $arg{copath} ? rmtree ([$arg{copath}]) : unlink($arg{copath});
}

sub do_proplist {
    my ($info, %arg) = @_;

    my ($txn, $xdroot);
    my $props = {};
    my $entry = $info->{checkout}->get_single ($arg{copath});
    $entry->{schedule} ||= '';
    $entry->{newprop} ||= {};

    if ($arg{rev}) {
	$xdroot = $arg{repos}->fs->revision_root ($arg{rev});
    }
    elsif ($entry->{schedule} eq 'add') {
    }
    else {
	($txn, $xdroot) = create_xd_root ($info, %arg);

	die "$arg{copath} ($arg{path})not under version control"
	    if $xdroot->check_path ($arg{path}) == $SVN::Node::none;
    }

    $txn->abort if $txn;

    $props = $xdroot->node_proplist ($arg{path}) if $xdroot;

    return {%$props,
	    %{$entry->{newprop}}};

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
    $info->{checkout}->store_single ($arg{copath},
				     {%{$info->{checkout}->get_single ($arg{copath})},
				      schedule =>
				      $entry->{schedule} || 'prop',
				      newprop => {%values,
						  $arg{propname} =>
						  $arg{propvalue},
						 }});
    print " M $arg{copath}\n" unless $arg{quiet};

    $txn->abort if $txn;
}

sub do_revert {
    my ($info, %arg) = @_;

    my $revert = sub {
	# revert dir too...
	open my ($fh), '>', $_[1];
	my $content = $arg{repos}->fs->revision_root ($info->{checkout}->get ($_[1])->{revision})->file_contents ($_[0]);
	local $/;
	my $buf = <$content>;
	print $fh $buf;
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

    if ($arg{recursive}) {
	checkout_crawler ($info,
			  ( %arg,
			    cb_add => $unschedule,
			    cb_prop => $unschedule,
			    cb_changed => $revert,
			    cb_delete => $revert,
			  ));
    }
    else {
	if (exists $info->{checkout}->get ($arg{copath})->{schedule}) {
	    &$unschedule (undef, $arg{copath});
	}
	else {
	    &$revert ($arg{path}, $arg{copath});
	}
    }
}


use File::Find;

sub checkout_crawler {
    my ($info, %arg) = @_;

    my %schedule = map {$_ => $info->{checkout}->get ($_)->{schedule}}
	$info->{checkout}->find ($arg{copath}, {schedule => qr'.*'});

    my %torm;
    for ($info->{checkout}->find ($arg{copath}, {schedule => 'delete'})) {
	die "auto anchor not supported yet, call with upper level directory"
	    if $_ eq $arg{copath};

	my (undef,$pdir,undef) = File::Spec->splitpath ($_);
	chop $pdir;

	push @{$torm{$pdir}}, $_
	    unless exists $schedule{$pdir} && $schedule{$pdir} eq 'delete';
    }

    my ($txn, $xdroot) = create_xd_root ($info, %arg);

    find(sub {
	     my $cpath = $File::Find::name;
	     my $hasprop;

	     # seems gotta do anchor/target in a upper level?
	     if (-d $arg{copath}) {
		 $cpath =~ s|^$arg{copath}/|$arg{path}/|;
		 $cpath = $arg{path} if $cpath eq $arg{copath};
	     }
	     else {
		 my (undef, $anchor) = File::Spec->splitpath ($arg{copath});
		 my (undef, $canchor) = File::Spec->splitpath ($arg{path});
		 $cpath =~ s|^$anchor|$canchor|;
	     }
	     if (exists $torm{$File::Find::name}) {
		 my @items = ($arg{delete_only_parent}) ?
		     @{$torm{$File::Find::name}} :
			 $info->{checkout}->find ($File::Find::name,
						  {schedule => 'delete'});

		 for (@items) {
		     my $rmpath = $_;
		     s|^$arg{copath}/|$arg{path}/|;
		     &{$arg{cb_delete}} ($_, $rmpath, $xdroot)
			 if $arg{cb_delete};
		 }
	     }
	     if (exists $schedule{$File::Find::name}) {
		 # we need an option to decide how to use the add/prop callback
		 # 1. akin to the editor interface, add and prop are separate
		 if ($schedule{$File::Find::name} eq 'add') {
		     &{$arg{cb_add}} ($cpath, $File::Find::name, $xdroot)
			 if $arg{cb_add};
		     return;
		 }
		 $hasprop++
		     if $schedule{$File::Find::name} eq 'prop';
	     }
	     my $kind = $xdroot->check_path ($cpath);
	     if ($kind == $SVN::Node::none) {
		 &{$arg{cb_unknown}} ($cpath, $File::Find::name, $xdroot)
		     if $arg{cb_unknown};
		 return;
	     }
	     if (-d $File::Find::name) {
		 &{$arg{cb_prop}} ($cpath, $File::Find::name, $xdroot)
		     if $hasprop && $arg{cb_prop};
		 return;
	     }

	     my $fh = get_fh ($xdroot, '<', $cpath, $File::Find::name);
	     if ($arg{cb_changed} && SVN::XD::MergeEditor::md5($fh) ne
		 $xdroot->file_md5_checksum ($cpath)) {
		 &{$arg{cb_changed}} ($cpath, $File::Find::name, $xdroot);
	     }
	     elsif ($hasprop &&$arg{cb_prop}) {
		 &{$arg{cb_prop}} ($cpath, $File::Find::name, $xdroot);
	     }
	  }, $arg{copath});
    $txn->abort if $txn;
}

sub do_merge {
    my ($info, %arg) = @_;
    # XXX: reorganize these shit
    my ($anchor, $target) = ($arg{path});
    my ($base_anchor, $base_target) = ($arg{basepath} || $arg{path});
    my ($txn, $xdroot);
    my ($tgt_anchor, $tgt) = ($arg{dpath});
    my ($storage, $findanchor, %cb);

    my $fs = $arg{repos}->fs;

    if ($arg{copath}) {
	($txn, $xdroot) = create_xd_root ($info, (%arg, path => $arg{dpath}));
    }
    else {
	$xdroot = $fs->revision_root ($arg{fromrev});
    }

    $findanchor = 1
	unless $xdroot->check_path ($arg{path}) == $SVN::Node::dir;

    # decide anchor / target
    if ($findanchor) {
	(undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
	(undef,$base_anchor,$base_target) = File::Spec->splitpath ($base_anchor);
	undef $target unless $target;
	undef $base_target unless $base_target;
	chop $anchor if length($anchor) > 1;
	chop $base_anchor if length($base_anchor) > 1;

	(undef,$tgt_anchor,$tgt) = File::Spec->splitpath ($arg{dpath});
	unless ($arg{copath}) {
	    # XXX: merge into repos requiring anchor is not tested yet
	    $storage = SVN::XD::TranslateEditor->new
		( translate => sub { return unless $tgt;
				     my $t = translator($target);
				     $_[0] = $tgt, return
					 if $target && $target eq $_[0];
				     $_[0] =~ s|$t|$tgt/|
					 or die "unable to translate $_[0] with $t" },
		);
	}
    }

    # setup editor and callbacks
    if ($arg{copath}) {
	$storage = SVN::XD::Editor->new
	    ( copath => $arg{copath},
	      oldroot => $xdroot,
	      newroot => $xdroot,
	      anchor => $tgt_anchor,
	      get_copath => sub { my $t = translator($target);
				  $_[0] = $arg{copath}, return
				     if $target && $target eq $_[0];
				  $_[0] =~ s|$t|$arg{copath}/|
				      or die "unable to translate $_[0] with $t" },
	      checkout => $info->{checkout},
	      info => $info,
	      check_only => $arg{check_only},
	    );
	%cb = xd_storage_cb ($info, $tgt_anchor, $tgt, $arg{copath}, $xdroot),
    }
    else {
	my $editor = $arg{editor};
	my $base_rev = $arg{base_rev};

	$editor ||= SVN::Delta::Editor->new
	    ( SVN::Repos::get_commit_editor
	      ( $arg{repos},
		"file://$arg{repospath}",
		$tgt_anchor,
		$ENV{USER}, $arg{message},
		sub { print "Committed revision $_[0].\n" }
	      ));

	$base_rev ||= $arg{repos}->fs->youngest_rev;

	$editor = SVN::XD::CheckEditor->new ($editor)
	    if $arg{check_only};

	my $root = $fs->revision_root ($fs->youngest_rev);
	($storage ? $storage->{_editor} : $storage) = $editor;
	# XXX: need translator
	%cb = ( cb_exist =>
		sub { my $path = $tgt_anchor.'/'.shift;
		      $root->check_path ($path) != $SVN::Node::none;
		  },
		cb_rev => sub { $base_rev; },
		cb_conflict => sub { die "conflict $tgt_anchor/$_[0]"; },
		cb_localmod =>
		sub { my ($path, $checksum) = @_;
		      $path = "$tgt_anchor/$path";
		      my $md5 = $root->file_md5_checksum ($path);
		      return if $md5 eq $checksum;
		      return [$root->file_contents ($path), undef, $md5];
		  },
	      );
    }

    my $editor = SVN::XD::MergeEditor->new
	( anchor => $anchor,
	  base_anchor => $base_anchor,
	  base_root => $fs->revision_root ($arg{fromrev}),
	  target => $target,
	  cb_merged => $arg{cb_merged},
	  storage => $storage,
	  %cb,
	);

    SVN::Repos::dir_delta ($fs->revision_root ($arg{fromrev}),
			   $base_anchor, $base_target,
			   $fs->revision_root ($arg{torev}), $arg{path},
			   $editor, undef,
			   1, 1, 0, 1);

    $txn->abort if $txn;
}

use SVN::Simple::Edit;

sub get_commit_editor {
    my ($xdroot, $committed, $path, %arg) = @_;
    return SVN::Simple::Edit->new
	(_editor => [SVN::Repos::get_commit_editor($arg{repos},
						   "file://$arg{repospath}",
						   $path,
						   $arg{author}, $arg{message},
						   $committed)],
	 base_path => $path,
	 root => $xdroot,
	 missing_handler =>
	 SVN::Simple::Edit::check_missing ());
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

sub do_commit {
    my ($info, %arg) = @_;

    die "commit without targets?" if $#{$arg{targets}} < 0;

    print "commit message from $arg{author}:\n$arg{message}\n";
    my ($anchor, $target) = $arg{path};
    my ($coanchor, $copath) = $arg{copath};

    unless (-d $coanchor) {
	(undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
	chop $anchor if length ($anchor) > 1;
    }
    elsif (!$anchor) {
	$coanchor .= '/';
    }

    (undef,$coanchor,$copath) = File::Spec->splitpath ($arg{copath})
	if $target;

    print "commit from $arg{path} (anchor $anchor) <- $arg{copath}\n";
    print "targets:\n";
    print "$_->[1]\n" for @{$arg{targets}};

    my ($txn, $xdroot) = create_xd_root ($info, %arg);

    my $committed = sub {
	my ($rev) = @_;
	for (reverse @{$arg{targets}}) {
	    my $result_rev = $_->[0] eq 'D' ? undef : $rev;
	    my $store = ($_[0] eq 'D' || -d $_->[1]) ?
		'store_recursively' : 'store';
	    $info->{checkout}->$store ($_->[1], { schedule => undef,
						  newprop => undef,
						  revision => $result_rev,
						});

	}
	my $root = $arg{repos}->fs->revision_root ($rev);
	for (@{$arg{targets}}) {
	    next if $_->[0] eq 'D';
	    my ($action, $tpath) = @$_;
	    my $cpath = $tpath;
	    $tpath =~ s|^$coanchor||;
	    my $via = get_keyword_layer ($root, "$anchor/$tpath");
	    next unless $via;

	    my $fh;
	    open $fh, '<', $cpath
		if $_->[0] eq 'A';
	    $fh ||= get_fh ($xdroot, '<', "$anchor/$tpath", $cpath);
	    # XXX: beware of collision
	    # XXX: fix permission etc also
	    my $fname = "$cpath.svk.old";
	    rename $cpath, $fname;
	    open my ($newfh), ">$via", $cpath;
	    local $/ = \16384;
	    while (<$fh>) {
		print $newfh $_;
	    }
	    close $fh;
	    unlink $fname;
	}
	print "Committed revision $rev.\n";
    };

    my $edit = get_commit_editor ($xdroot, $committed, $anchor, %arg);

    $edit->open_root();
    for (@{$arg{targets}}) {
	my ($action, $tpath) = @$_;
	my $cpath = $tpath;
	$tpath =~ s|^$coanchor|| or die "absurb path $tpath not under $coanchor";
	if ($action eq 'D') {
	    $edit->delete_entry ($tpath);
	    next;
	}
	if (-d $cpath) {
	    $edit->add_directory ($tpath)
		unless $action eq 'P';
	    my $props = $info->{checkout}->get_single ($cpath);
	    next unless $props->{newprop};
	    while (my ($key, $value) = each (%{$props->{newprop}})) {
		$edit->change_dir_prop ($tpath, $key, $value);
	    }
	    next;
	}
	if ($action eq 'A') {
	    $edit->add_file ($tpath);
	}
	my $props = $info->{checkout}->get_single ($cpath);
	if ($props->{newprop}) {
	    while (my ($key, $value) = each (%{$props->{newprop}})) {
		$edit->change_file_prop ($tpath, $key, $value);
	    }
	}
	next if $action eq 'P';
	my $fh;
	open $fh, '<', $cpath
	    if $action eq 'A';
	$fh ||= get_fh ($xdroot, '<', "$anchor/$tpath", $cpath);
	my $md5 = SVN::XD::MergeEditor::md5 ($fh);
	seek $fh, 0, 0;
	$edit->modify_file ($tpath, $fh, $md5)
	    unless $action eq 'P';
    }
    $edit->close_edit();
    $txn->abort if $txn;
}

sub get_keyword_layer {
    my ($root, $path) = @_;
    my $k = eval { $root->node_prop ($path, 'svn:keywords') };
    use Carp;
    confess "can't get keyword layer for $path: $@" if $@;

    return '' unless $k;

    # XXX: should these respect svm related stuff
    my %kmap = ( LastChangedDate =>
		 sub { my ($root, $path) = @_;
		       my $rev = $root->node_created_rev ($path);
		       my $fs = $root->fs;
		       $fs->revision_prop ($rev, 'svn:date');
		   },
		 Rev =>
		 sub { my ($root, $path) = @_;
		       $root->node_created_rev ($path);
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
	       );

    my @key = grep {exists $kmap{$_}} (split ',',$k);
    return '' unless $#key >= 0 ;

    my $keyword = '('.join('|', @key).')';

    my $p = PerlIO::via::keyword->new
	({translate => sub { $_[1] =~ s/\$($keyword)[:\w\s\-\.\/]*\$/"\$$1: ".&{$kmap{$1}}($root, $path).'$'/e },
	  undo => sub { $_[1] =~ s/\$($keyword)[:\w\s\-\.\/]*\$/\$$1\$/}});
    return $p->via;
}

sub get_fh {
    my ($root, $mode, $path, $fname) = @_;
    my $via = get_keyword_layer ($root, $path);
    open my ($fh), "$mode$via", $fname;
    return $fh;
}

sub md5file {
    my $fname = shift;
    open my $fh, '<', $fname;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

package SVN::XD::TranslateEditor;
use base qw/SVN::Delta::Editor/;

sub add_file {
    my ($self, $path, @arg) = @_;
    &{$self->{translate}} ($path);
    $self->{_editor}->add_file ($path, @arg);
}

sub open_file {
    my ($self, $path, @arg) = @_;
    &{$self->{translate}} ($path);
    $self->{_editor}->open_file ($path, @arg);
}

sub add_directory {
    my ($self, $path, @arg) = @_;
    &{$self->{translate}} ($path);
    $self->{_editor}->add_directory ($path, @arg);
}

sub open_directory {
    my ($self, $path, @arg) = @_;
    &{$self->{translate}} ($path);
    $self->{_editor}->open_directory ($path, @arg);
}

sub delete_entry {
    my $self = shift;
    my $path = shift;
    &{$self->{translate}} ($path);
    $self->{_editor}->delete_entry ($path, @_);
}

package SVN::XD::CheckEditor;
our @ISA = qw(SVN::Delta::Editor);

sub close_edit {
    my $self = shift;
    print "Commit checking finished\n";
    $self->{_editor}->abort_edit (@_);
}

package SVN::XD::Editor;
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
	my (undef,$dir,$file) = File::Spec->splitpath ($copath);
	my $basename = "$dir.svk.$file.base";
	$base = SVN::XD::get_fh ($self->{oldroot}, '<',
				 "$self->{anchor}/$path", $copath);
	if ($checksum) {
	    my $md5 = SVN::XD::MergeEditor::md5($base);
	    die "source checksum mismatch" if $md5 ne $checksum;
	    seek $base, 0, 0;
	}
	rename ($copath, $basename);
	$self->{base}{$path} = [$base, $basename];
    }
    my $fh = SVN::XD::get_fh ($self->{newroot}, '>',
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
    }
    elsif (!$self->{update} && !$self->{check_only}) {
	SVN::XD::do_add ($self->{info}, copath => $copath, quiet => 1);
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
					  {revision => $self->{revision}})
	if $self->{update};
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    # XXX: do executable unset also.
    $self->{exe}{$path}++
	if $name eq 'svn:executable' && defined $value;
    SVN::XD::do_propset ($self->{info},
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

package SVN::XD::MergeEditor;
our @ISA = qw(SVN::Delta::Editor);
use Digest::MD5;
use File::Temp qw/:mktemp/;

sub md5 {
    my $fh = shift;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
    $self->{storage}->set_target_revision ($revision);
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{baserev} = $baserev;
    $self->{storage_baton}{''} =
	$self->{storage}->open_root (&{$self->{cb_rev}}(''));
    return '';
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    # tag for merge of file adding
    $self->{info}{$path}{status} = (&{$self->{cb_exist}}($path) ? undef : ['A']);
    $self->{storage_baton}{$path} =
	$self->{storage}->add_file ($path, $self->{storage_baton}{$pdir}, @arg)
	if $self->{info}{$path}{status};
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, $rev, @arg) = @_;
    # modified but rm locally - tag for conflict?
    $self->{info}{$path}{status} = (&{$self->{cb_exist}}($path) ? [] : undef);
    $self->{storage_baton}{$path} =
	$self->{storage}->open_file ($path, $self->{storage_baton}{$pdir},
				     &{$self->{cb_rev}}($path), @arg)
	    if $self->{info}{$path}{status};
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $self->{info}{$path}{status};
    my ($base, $newname);
    unless ($self->{info}{$path}{status}[0]) { # open, has base
	if ($self->{info}{$path}{fh}{local} = 
	    &{$self->{cb_localmod}}($path, $checksum)) {
	    # retrieve base
	    $self->{info}{$path}{fh}{base} = [mkstemps("/tmp/svk-mergeXXXXX", '.tmp')];
	    my $rpath = $path;
	    $rpath = "$self->{base_anchor}/$rpath" if $self->{base_anchor};
	    my $buf = $self->{base_root}->file_contents ($rpath);
	    local $/;
	    $self->{info}{$path}{fh}{base}[0]->print(<$buf>);
	    seek $self->{info}{$path}{fh}{base}[0], 0, 0;
	    # get new
	    my ($fh, $file) = mkstemps("/tmp/svk-mergeXXXXX", '.tmp');
	    $self->{info}{$path}{fh}{new} = [$fh, $file];
	    return [SVN::TxDelta::apply ($self->{info}{$path}{fh}{base}[0],
					 $fh, undef, undef, $pool)];
	}
    }
    $self->{info}{$path}{status}[0] = 'U';
    return $self->{storage}->apply_textdelta ($self->{storage_baton}{$path},
					      $checksum, $pool);
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    my $info = $self->{info}{$path};
    my $fh = $info->{fh};
    no warnings 'uninitialized';

    # let close_directory reports about its children
    if ($info->{fh}{local}) {
	my ($orig, $new, $local) = map {$fh->{$_}[0]} qw/base new local/;
	seek $orig, 0, 0;
	open $new, $fh->{new}[1];
#	seek $local, 0, 0;
	{
	    local $/;
	    $orig = <$orig>;
	    $new = <$new>;
	    $local = <$local>;
	}

	if ($new eq $local) {
	    close $fh->{base}[0];
	    unlink $fh->{base}[1];
	    close $fh->{new}[0];
	    unlink $fh->{new}[1];

	    delete $self->{info}{$path};
	    $self->{storage}->close_file ($self->{storage_baton}{$path},
					  $checksum, $pool);
	    return;
	}

	my @mergearg =
	    ([split "\n", $orig],
	     [split "\n", $new],
	     [split "\n", $local],
	    );
	# merge consistencies check
	my $diff3 = Algorithm::Merge::diff3 (@mergearg);

	for (@$diff3) {
	    if ($_->[0] eq 'u' && ($_->[1] ne $_->[2] || $_->[2] ne $_->[3])) {
		my $file = '/tmp/svk-merge-bug.yml';
		unlink ($file);
		YAML::DumpFile ($file, $diff3);
		die "merge result inconsistent, please send the file $file to {clkao,jsmith}\@cpan.org";
	    }
	}

	# XXX: use traverse so we just output the result instead of
	# buffering it
	$info->{status}[0] = 'G';
	my $merged = eval {Algorithm::Merge::merge (@mergearg,
	     {CONFLICT => sub {
		  my ($left, $right) = @_;
		  $info->{status}[0] = 'C';
		  q{<!-- ------ START CONFLICT ------ -->},
		  (@$left),
		  q{<!-- ---------------------------- -->},
		  (@$right),
		  q{<!-- ------  END  CONFLICT ------ -->},
	      }}) };
	die $@ if $@;

	close $fh->{base}[0];
	unlink $fh->{base}[1];
	close $fh->{new}[0];
	unlink $fh->{new}[1];
	my $handle = $self->{storage}->
	    apply_textdelta ($self->{storage_baton}{$path}, $fh->{local}[2],
			     $pool);

	$merged = (join("\n", @$merged)."\n");
	SVN::TxDelta::send_string ($merged, @$handle, $pool)
		if $handle && $#{$handle} > 0;
	$checksum = Digest::MD5::md5_hex ($merged);
	&{$self->{cb_conflict}} ($path)
	    if $info->{status}[0] eq 'C';
    }

    if ($info->{status}) {
	print sprintf ("%1s%1s \%s\n", $info->{status}[0],
		       $info->{status}[1], $path);
	$self->{storage}->close_file ($self->{storage_baton}{$path},
				      $checksum, $pool);
    }
    else {
	print "   $path - skipped\n";
    }
    delete $self->{info}{$path};
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    $self->{storage_baton}{$path} =
	$self->{storage}->add_directory ($path, $self->{storage_baton}{$pdir},
					 @arg);
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, @arg) = @_;
    $self->{storage_baton}{$path} =
	$self->{storage}->open_directory ($path, $self->{storage_baton}{$pdir},
					  &{$self->{cb_rev}}($path), @arg);
    return $path;
}

sub close_directory {
    my ($self, $path, $pool) = @_;
    no warnings 'uninitialized';

    for (grep {$path ? "$path/" eq substr ($_, 0, length($path)+1) : 1}
	 keys %{$self->{info}}) {
	print sprintf ("%1s%1s \%s\n", $self->{info}{$_}{status}[0],
		       $self->{info}{$_}{status}[1], $_);
	delete $self->{info}{$_};
    }

    &{$self->{cb_merged}} ($self->{storage}, $self->{storage_baton}{''}, $pool)
	if $path eq '' && $self->{cb_merged};

    $self->{storage}->close_directory ($self->{storage_baton}{$path}, $pool);
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
    return unless &{$self->{cb_exist}}($path);

    $self->{storage}->delete_entry ($path, $revision,
				    $self->{storage_baton}{$pdir}, @arg);
    $self->{info}{$path}{status} = ['D'];
}

sub change_file_prop {
    my ($self, $path, @arg) = @_;
    return unless $self->{info}{$path}{status};
    $self->{storage}->change_file_prop ($self->{storage_baton}{$path}, @arg);
    $self->{info}{$path}{status}[1] = 'U';
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
    return unless $self->{info}{$path}{status};
    return if $arg[0] eq 'svk:merge';
    $self->{storage}->change_dir_prop ($self->{storage_baton}{$path}, @arg);
    $self->{info}{$path}{status}[1] = 'U';
}

sub close_edit {
    my ($self, @arg) = @_;
    $self->{storage}->close_edit(@arg);
}

#!/usr/bin/perl -w
use strict;
package PerlIO::via::keyword;

sub PUSHED {
    die "this should now be via directly"
	if $_[0] eq __PACKAGE__;
    bless \*PUSHED, $_[0];
}

sub translate {
}

sub undo {
}

sub FILL {
    my $line = readline( $_[1] );
    $_[0]->undo ($line) if defined $line;
    $line;
}

sub WRITE {
    my $buf = $_[1];
    $_[0]->translate($buf);
    (print {$_[2]} $buf) ? length($buf) : -1;
}

sub SEEK {
    seek ($_[3], $_[1], $_[2]);
}

sub new {
    my ($class, $arg) = @_;
    my $self = {};
    my $package = 'PerlIO::via::keyword'.substr("$self", 7, -1);
    eval qq|
package $package;
our \@ISA = qw($class);

1;
| or die $@;

    no strict 'refs';
    for (keys %$arg) {
	*{"$package\::$_"} = $arg->{$_};
    }
    bless $self, $package;
    return $self;
}

sub via {
    ':via('.ref ($_[0]).')';
}

1;
