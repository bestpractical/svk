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
    my ($info, $target, $copath) = @_;
    my $t = translator ($target, $copath);

    return
	( cb_exist => sub { $_ = shift; s|$t|$copath/|; -e $_},
	  cb_rev => sub { $_ = shift; s|$t|$copath/|;
			  $info->{checkout}->get ($_)->{revision} },
	  cb_conflict => sub { $_ = shift; s|$t|$copath/|;
			       $info->{checkout}->store ($_, {conflict => 1})},
	  cb_localmod => sub { my ($path, $checksum) = @_;
			       $_ = $path; s|$t|$copath/|;
			       open my ($base), '<', $_;
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

    my $storage = SVN::XD::TranslateEditor->new
	( translate => sub { my $t = translator($target);
			     $_[0] = $arg{copath}, return
				 if $target && $target eq $_[0];
			     $_[0] =~ s|$t|$arg{copath}/|
				 or die "unable to translate $_[0] with $t" },
	);

    $storage->{_editor} = SVN::XD::Editor->new
	( copath => $arg{copath},
	  checkout => $info->{checkout},
	  info => $info,
	  update => 1,
	);

    my $editor = SVN::XD::MergeEditor->new
	(_debug => 0,
	 fs => $fs,
	 anchor => $anchor,
	 base_root => $xdroot,
	 target => $target,
	 storage => $storage,
	 xd_storage_cb ($info, $target, $arg{copath}),
	);

#    $editor = SVN::Delta::Editor->new(_debug=>1),

    SVN::Repos::dir_delta ($xdroot, $anchor, $target,
			   $fs->revision_root ($arg{rev}), $arg{path},
			   $editor,
			   1, 1, 0, 1);

    SVN::Fs::close_txn ($txn) if $txn;
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

    $txn->close if $txn;

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
    $info->{checkout}->store_single ($arg{copath}, { schedule =>
					      $entry->{schedule} || 'prop',
					      newprop => {%values,
							  $arg{propname} =>
							  $arg{propvalue},
							 }});
    print " M $arg{copath}\n" unless $arg{quiet};

    SVN::Fs::close_txn ($txn) if $txn;
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

	     if ($arg{cb_changed} && md5file($File::Find::name) ne
		 $xdroot->file_md5_checksum ($cpath)) {
		 &{$arg{cb_changed}} ($cpath, $File::Find::name, $xdroot)
	     }
	     elsif ($hasprop &&$arg{cb_prop}) {
		 &{$arg{cb_prop}} ($cpath, $File::Find::name, $xdroot);
	     }
	  }, $arg{copath});
    SVN::Fs::close_txn ($txn) if $txn;
}

sub do_merge {
    my ($info, %arg) = @_;
    my ($anchor, $target) = ($arg{path});
    my ($txn, $xdroot);
    my ($basepath, $tgt) = ($arg{dpath});
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
	undef $target unless $target;
	chop $anchor if length($anchor) > 1;

	unless ($arg{copath}) {
	    # XXX: merge into repos requiring anchor is not tested yet
	    (undef,$basepath,$tgt) = File::Spec->splitpath ($arg{dpath});
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
	$storage = SVN::XD::TranslateEditor->new
	    ( translate => sub { my $t = translator($target);
				 $_[0] = $arg{copath}, return
				     if $target && $target eq $_[0];
				 $_[0] =~ s|$t|$arg{copath}/|
				     or die "unable to translate $_[0] with $t" },
	    );
	$storage->{_editor} = SVN::XD::Editor->new
	    ( copath => $arg{copath},
	      checkout => $info->{checkout},
	      info => $info,
	      check_only => $arg{check_only},
	    );
	%cb = xd_storage_cb ($info, $target, $arg{copath}),
    }
    else {
	my $editor;
	my $base_rev;
	eval 'require SVN::Mirror' and do {
	    my $auth = SVN::Core::auth_open
		([SVN::Client::get_simple_provider (),
		  SVN::Client::get_ssl_server_file_provider (),
		  SVN::Client::get_username_provider ()]);

	    my $m = SVN::Mirror->new(target_path => $arg{dpath},
				     target => $arg{repospath},
				     pool => SVN::Pool->new, auth => $auth,
				     get_source => 1);
	    eval { $m->init };
	    # commit back to mirror
	    unless ($@) {
		print "Merge back to SVN::Mirror source $m->{source}.\n";
		if ($arg{check_only}) {
		    print "Check against mirrored directory locally.\n";
		}
		else {
		    ($base_rev, $editor) = $m->get_merge_back_editor
			($arg{message},
			 sub { print "Merge back committed as revision $_[0].\n" }
			);
		}
	    }
	};

	$editor ||= SVN::Delta::Editor->new
	    ( SVN::Repos::get_commit_editor
	      ( $arg{repos},
		"file://$arg{repospath}",
		$basepath,
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
		sub { my $path = $basepath.'/'.shift;
		      $root->check_path ($path) != $SVN::Node::none;
		  },
		cb_rev => sub { $base_rev; },
		cb_conflict => sub { die "conflict $basepath/$_[0]"; },
		cb_localmod =>
		sub { my ($path, $checksum) = @_;
		      $path = "$basepath/$path";
		      my $md5 = $root->file_md5_checksum ($path);
		      return if $md5 eq $checksum;
		      return [$root->file_contents ($path), undef, $md5];
		  },
	      );
    }

    my $editor = SVN::XD::MergeEditor->new
	( anchor => $anchor,
	  base_root => $fs->revision_root ($arg{fromrev}),
	  target => $target,
	  storage => $storage,
	  %cb,
	);

    SVN::Repos::dir_delta ($fs->revision_root ($arg{fromrev}),
			   $anchor, $target,
			   $fs->revision_root ($arg{torev}), $arg{path},
			   $editor,
			   1, 1, 0, 1);

    SVN::Fs::close_txn ($txn) if $txn;
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
	print "Committed revision $rev.\n";
    };

    print "commit message from $arg{author}:\n$arg{message}\n";
    my ($anchor, $target) = $arg{path};
    my ($coanchor, $copath) = $arg{copath};

    unless (-d $coanchor ) {
	(undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
	chop $anchor if length ($anchor) > 1;
    }

    (undef,$coanchor,$copath) = File::Spec->splitpath ($arg{copath})
	if $target;

    print "commit from $arg{path} (anchor $anchor) <- $arg{copath}\n";
    print "targets:\n";
    print "$_->[1]\n" for @{$arg{targets}};

    my ($txn, $xdroot) = create_xd_root ($info, %arg);

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
	open my ($fh), '<', $cpath;
	my $md5 = md5file ($cpath);
	if ($action eq 'A') {
	    $edit->add_file ($tpath);
	}
	my $props = $info->{checkout}->get_single ($cpath);
	if ($props->{newprop}) {
	    while (my ($key, $value) = each (%{$props->{newprop}})) {
		$edit->change_file_prop ($tpath, $key, $value);
	    }
	}
	$edit->modify_file ($tpath, $fh, $md5)
	    unless $action eq 'P';
    }
    $edit->close_edit();
    SVN::Fs::close_txn ($txn) if $txn;
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
    my ($self, $path) = @_;
    &{$self->{translate}} ($path);
    $self->{_editor}->add_file ($path);
}

sub open_file {
    my ($self, $path) = @_;
    &{$self->{translate}} ($path);
    $self->{_editor}->open_file ($path);
}

sub add_directory {
    my ($self, $path) = @_;
    &{$self->{translate}} ($path);
    $self->{_editor}->add_directory ($path);
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
    return $self->{copath};
}

sub add_file {
    my ($self, $path) = @_;
    die "$path already exists" if -e $path;
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    die "path not exists" unless -e $path;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    my $base;
    return if $self->{check_only};
    if (-e $path) {
	my (undef,$dir,$file) = File::Spec->splitpath ($path);
	my $basename = "$dir.svk.$file.base";
	open $base, '<', $path;
	if ($checksum) {
	    my $md5 = SVN::XD::MergeEditor::md5($base);
	    die "source checksum mismatch" if $md5 ne $checksum;
	    seek $base, 0, 0;
	}
	rename ($path, $basename);
	$self->{base}{$path} = [$base, $basename];

    }
    open my ($fh), '+>', $path or warn "can't open $path";
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty($pool),
				 $fh, undef, undef, $pool)];
}

sub close_file {
    my ($self, $path) = @_;
    if ($self->{base}{$path}) {
	close $self->{base}{$path}[0];
	unlink $self->{base}{$path}[1];
    }
    elsif (!$self->{update} && !$self->{check_only}) {
	SVN::XD::do_add ($self->{info}, copath => $path, quiet => 1);
    }
    $self->{checkout}->store ($path, {revision => $self->{revision}})
	if $self->{update};
}

sub add_directory {
    my ($self, $path) = @_;
    mkdir ($path);
    return $path;
}

sub open_directory {
    my ($self, $path) = @_;
    return $path;
}

sub delete_entry {
    my ($self, $path, $revision) = @_;
    # check if everyone under $path is sane for delete";
    return if $self->{check_only};
    -d $path ? rmtree ([$path]) : unlink($path);
}

sub close_directory {
    my ($self, $path) = @_;
    $self->{checkout}->store_recursively ($path,
					  {revision => $self->{revision}})
	if $self->{update};
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    SVN::XD::do_propset ($self->{info},
			 quiet => 1,
			 copath => $path,
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
    $self->{storage_baton}{''} = $self->{storage}->open_root ($baserev);
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
	    $rpath = "$self->{anchor}/$rpath" if $self->{anchor};
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
	# XXX: use traverse so we just output the result instead of
	# buffering it
	$info->{status}[0] = 'G';
	my $merged = Algorithm::Merge::merge
	    ([split "\n", $orig],
	     [split "\n", $new],
	     [split "\n", $local],
	     {CONFLICT => sub {
		  my ($left, $right) = @_;
		  $info->{status}[0] = 'C';
		  q{<!-- ------ START CONFLICT ------ -->},
		  (@$left),
		  q{<!-- ---------------------------- -->},
		  (@$right),
		  q{<!-- ------  END  CONFLICT ------ -->},
	      }},
	    );

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
    my ($self, $path) = @_;
    no warnings 'uninitialized';

    for (grep {$path ? "$path/" eq substr ($_, 0, length($path)+1) : 1}
	 keys %{$self->{info}}) {
	print sprintf ("%1s%1s \%s\n", $self->{info}{$_}{status}[0],
		       $self->{info}{$_}{status}[1], $_);
	delete $self->{info}{$_};
    }

    $self->{storage}->close_directory ($self->{storage_baton}{$path});
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
    $self->{storage}->delete_entry ($path, $revision,
				    $self->{storage_baton}{$pdir}, @arg);
    $self->{info}{$path}{status} = ['D'];
}

sub change_file_prop {
    my ($self, $path, @arg) = @_;
    $self->{storage}->change_file_prop ($self->{storage_baton}{$path}, @arg);
    $self->{info}{$path}{status}[1] = 'U';
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
    $self->{storage}->change_dir_prop ($self->{storage_baton}{$path}, @arg);
    $self->{info}{$path}{status}[1] = 'U';
}

sub close_edit {
    my ($self, @arg) = @_;
    $self->{storage}->close_edit(@arg);
}

1;
