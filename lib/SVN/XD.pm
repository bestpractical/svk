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

sub xd_storage_cb {
    my ($info, $target, $copath) = @_;
    return
	( cb_exist => sub { $_ = shift; s|^$target/|$copath/|; -e $_},
	  cb_conflict => sub { $_ = shift;s|^$target/|$copath/|;
			       $info->{checkout}->store ($_, {conflict => 1})},
	  cb_localmod => sub { my ($path, $checksum) = @_;
			       $path =~ s|^$target/|$copath/|;
			       open my ($base), '<', $path;
			       my $md5 = SVN::XD::MergeEditor::md5 ($base);
			       return undef if $md5 eq $checksum;
			       seek $base, 0, 0;
			       return [$base, $path];
			   });
}

sub do_update {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $xdroot;
    my $txn;

    print "syncing $arg{depotpath}($arg{path}) to $arg{copath} to $arg{rev}\n";
    my (undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
    my (undef,undef,$copath) = File::Spec->splitpath ($arg{copath});
    if ($anchor eq '/' && $target eq '') {
	$anchor = '';
	$target = '/';
    }
    chop $anchor if length($anchor) > 1;

    ($txn, $xdroot) = create_xd_root ($info, %arg);

    my $mtarget = $target eq '/' ? '' : $target;

    my $editor = SVN::XD::MergeEditor->new
	(_debug => 0,
	 fs => $fs,
	 anchor => $anchor,
	 xdroot => $xdroot,
	 target => $mtarget,
	 storage => SVN::XD::Editor->new
	 ( target => $mtarget,
	   copath => $arg{copath},
	   checkout => $info->{checkout},
	   update => 1,
	 ),
	 xd_storage_cb ($info, $mtarget, $arg{copath}),
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

    find(sub {
	     my $cpath = $File::Find::name;
	     # do dectation also
	     $info->{checkout}->store ($cpath, { schedule => 'add' });
	     print "A  $cpath\n";
	 }, $arg{copath});

    $info->{checkout}->store ($arg{copath}, { schedule => 'add' });
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

sub do_propset {
    my ($info, %arg) = @_;
    my %values;

    my ($txn, $xdroot) = create_xd_root ($info, %arg);

    die "$arg{copath} ($arg{path})not under version control"
	if $xdroot->check_path ($arg{path}) == $SVN::Node::none;

    #XXX: support working on multiple paths and recursive
    my ($data, @where) = $info->{checkout}->get ($arg{copath});
    if ($where[-1] eq $arg{copath}) {
	die "$arg{copath} is already schedule for delete"
	    if $data->{schedule} eq 'delete';
	%values = %{$data->{newprop}}
	    if exists $data->{schedule};
    }
    $info->{checkout}->store ($arg{copath}, { schedule =>
					      $data->{schedule} || 'prop',
					      newprop => {%values,
							  $arg{propname} =>
							  $arg{propvalue},
							 }});
    print " M $arg{copath}\n";

    SVN::Fs::close_txn ($txn) if $txn;
}

sub do_revert {
    my ($info, %arg) = @_;

    my $revert = sub {
	# revert dir too...
	warn "$_[1] already exists" if -e $_[1];
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

    checkout_crawler ($info,
		      (%arg,
		       cb_add => $unschedule,
		       cb_prop => $unschedule,
		       cb_changed => $revert,
		       cb_delete => $revert,
		      )
		     );
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
		 if ($schedule{$File::Find::name} eq 'prop') {
		     &{$arg{cb_prop}} ($cpath, $File::Find::name, $xdroot)
			 if $arg{cb_prop};
		     return;
		 }
	     }
	     my $kind = $xdroot->check_path ($cpath);
	     if ($kind == $SVN::Node::none) {
		 &{$arg{cb_unknown}} ($cpath, $File::Find::name, $xdroot)
		     if $arg{cb_unknown};
		 return;
	     }
	     return if -d $File::Find::name;
	     &{$arg{cb_changed}} ($cpath, $File::Find::name, $xdroot)
		 if $arg{cb_changed} && md5file($File::Find::name) ne
		     $xdroot->file_md5_checksum ($cpath);
	  }, $arg{copath});
    SVN::Fs::close_txn ($txn) if $txn;
}

sub do_merge {
    my ($info, %arg) = @_;

    my (undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
    my (undef,undef,$copath) = File::Spec->splitpath ($arg{copath});
    if ($anchor eq '/' && $target eq '') {
	$anchor = '';
	$target = '/';
    }
    chop $anchor if length($anchor) > 1;

    my $fs = $arg{repos}->fs;
    my ($txn, $xdroot) = create_xd_root ($info, %arg);

    my $mtarget = $target eq '/' ? '' : $target;
    my $editor = SVN::XD::MergeEditor->new
	(_debug => 0,
	 fs => $fs,
	 anchor => $anchor,
	 xdroot => $xdroot,
	 target => $mtarget,

	 storage => SVN::XD::Editor->new
	 ( target => $mtarget,
	   copath => $arg{copath},
	   checkout => $info->{checkout},
	   check_only => $arg{check_only},
	 ),
	 xd_storage_cb ($info, $mtarget, $arg{copath}),
	);

    SVN::Repos::dir_delta ($fs->revision_root ($arg{fromrev}),
			   $anchor, $target,
			   $fs->revision_root ($arg{torev}), $arg{path},
			   $editor,
			   1, 1, 0, 1);

    SVN::Fs::close_txn ($txn) if $txn;
}

use SVN::Simple::Edit;

sub do_commit {
    my ($info, %arg) = @_;

    my $committed = sub {
	my ($rev) = @_;
	for (@{$arg{targets}}) {
	    if ($_->[0] eq 'D') {
		$info->{checkout}->store_recursively ($_->[1], { schedule => undef,
						     revision => undef,
						   });
	    }
	    else {
		$info->{checkout}->store ($_->[1], { schedule => undef,
						     revision => $rev,
						   });
	    }
	}
	print "Committed revision $rev.\n";
    };

    print "commit message from $arg{author}:\n$arg{message}\n";
    my (undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
    my (undef,undef,$copath) = File::Spec->splitpath ($arg{copath});

    print "commit from $arg{path} ($anchor & $target) <- $arg{copath}\n";
    print "targets:\n";
    print "$_->[1]\n" for @{$arg{targets}};

    my ($txn, $xdroot) = create_xd_root ($info, %arg);

    my $edit = SVN::Simple::Edit->new
	(_editor => [SVN::Repos::get_commit_editor($arg{repos},
						   "file://$arg{repospath}",
						   $arg{path},
						   $arg{author}, $arg{message},
						   $committed)],
	 base_path => $arg{path},
	 root => $xdroot,
#	 root => $arg{repos}->fs->revision_root ($arg{baserev}),
	 missing_handler =>
	 SVN::Simple::Edit::check_missing ());

    $edit->open_root();
    for (@{$arg{targets}}) {
	my ($action, $tpath) = @$_;
	my $cpath = $tpath;
	$tpath =~ s|^$arg{copath}/|| or die "absurb path";
	if ($action eq 'D') {
	    $edit->delete_entry ($tpath);
	    next;
	}
	if (-d $cpath) {
	    $edit->add_directory ($tpath);
	    next;
	}
	open my ($fh), '<', $cpath;
	my $md5 = md5file ($cpath);
	if ($action eq 'A') {
	    $edit->add_file ($tpath);
	}
	$edit->modify_file ($tpath, $fh, $md5);
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
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    die "$path already exists" if -e $path;
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    die "path not exists" unless -e $path;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum) = @_;
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
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty(),
				 $fh, undef, undef)];
}

sub close_file {
    my ($self, $path) = @_;
    if ($self->{base}{$path}) {
	close $self->{base}{$path}[0];
	unlink $self->{base}{$path}[1];
    }
    $self->{checkout}->store ($path, {revision => $self->{revision}})
	if $self->{update};
}

sub add_directory {
    my ($self, $path) = @_;
    $path = $self->{copath} if $path eq $self->{copath};
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    mkdir ($path);
    return $path;
}

sub open_directory {
    my ($self, $path) = @_;
    $path = $self->{copath} if $path eq $self->{copath};
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    return $path;
}

sub delete_entry {
    my ($self, $path, $revision) = @_;
    $path =~ s|^$self->{target}/|$self->{copath}/|;
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
    my ($self, $path) = @_;
    # tag for merge of file adding
    $self->{info}{$path}{status} = (&{$self->{cb_exist}}($path) ? undef : ['A']);
    $self->{storage_baton}{$path} = $self->{storage}->add_file ($path)
	if $self->{info}{$path}{status};
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    # modified but rm locally - tag for conflict?
    $self->{info}{$path}{status} = (&{$self->{cb_exist}}($path) ? [] : undef);
    $self->{storage_baton}{$path} = $self->{storage}->open_file ($path)
	if $self->{info}{$path}{status};
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum) = @_;
    return unless $self->{info}{$path}{status};
    my ($base, $newname);
    unless ($self->{info}{$path}{status}[0]) { # open, has base
	if ($self->{info}{$path}{fh}{local} = 
	    &{$self->{cb_localmod}}($path, $checksum)) {
	    # retrieve base
	    $self->{info}{$path}{fh}{base} = [mkstemps("/tmp/svk-mergeXXXXX", '.tmp')];
	    my $rpath = $path;
	    $rpath = "$self->{anchor}/$rpath" if $self->{anchor};
	    my $buf = $self->{xdroot}->file_contents ($rpath);
	    $self->{info}{$path}{fh}{base}[0]->print(<$buf>);
	    seek $self->{info}{$path}{fh}{base}[0], 0, 0;
	    # get new
	    my ($fh, $file) = mkstemps("/tmp/svk-mergeXXXXX", '.tmp');
	    $self->{info}{$path}{fh}{new} = [$fh, $file];
	    return [SVN::TxDelta::apply ($self->{info}{$path}{fh}{base}[0],
					 $fh, undef, undef)];
	}
    }
    $self->{info}{$path}{status}[0] = 'U';
    return $self->{storage}->apply_textdelta ($self->{storage_baton}{$path},
					      $checksum);
}

sub close_file {
    my ($self, $path, $checksum) = @_;
    my $info = $self->{info}{$path};
    my $fh = $info->{fh};
    no warnings 'uninitialized';

    # let close_directory reports about its children
    if ($info->{fh}{local}) {
	my ($orig, $new, $local) = map {$fh->{$_}[0]} qw/base new local/;
	seek $orig, 0, 0;
	open $new, $fh->{new}[1];
	seek $local, 0, 0;
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
	    apply_textdelta ($self->{storage_baton}{$path});

	SVN::TxDelta::send_string ((join("\n", @$merged)."\n"), @$handle)
		if $handle;
	&{$self->{cb_conflict}} ($path)
	    if $info->{status}[0] eq 'C';
    }

    if ($info->{status}) {
	print sprintf ("%1s%1s \%s\n", $info->{status}[0],
		       $info->{status}[1], $path);
    }
    else {
	print "   $path - skipped\n";
    }
    $self->{storage}->close_file ($self->{storage_baton}{$path});
}

sub add_directory {
    my ($self, $path) = @_;
    $self->{storage_baton}{$path} = $self->{storage}->add_directory ($path);
    return $path;
}

sub open_directory {
    my ($self, $path) = @_;
    $self->{storage_baton}{$path} = $self->{storage}->open_directory ($path);
    return $path;
}

sub close_directory {
    my ($self, $path) = @_;
    $self->{storage}->close_directory ($self->{storage_baton}{$path});
    print ".  $path\n";
}

sub delete_entry {
    my ($self, $path, $revision) = @_;
    $self->{storage}->delete_entry ($path, $revision);
    $self->{info}{$path}{status} = ['D'];
}

sub close_edit {
    my ($self) = @_;
    $self->{storage}->close_edit();
}

1;
