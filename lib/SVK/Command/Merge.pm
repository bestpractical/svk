package SVK::Command::Merge;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::CommitStatusEditor;
use SVK::Command::Log;
use SVK::Util qw (get_buffer_from_editor);

sub options {
    ($_[0]->SUPER::options,
     'a|auto'		=> 'auto',
     'l|log'		=> 'log',
     'no-ticket'	=> 'no_ticket',
     'r|revision=s'	=> 'revspec');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return ($self->arg_depotpath ($arg[0]), $self->arg_co_maybe ($arg[1] || ''));
}

sub run {
    my ($self, $src, $dst) = @_;
    my ($fromrev, $torev, $cb_merged, $cb_closed);

    die "different repos?" unless $src->{repospath} eq $dst->{repospath};
    my $repos = $src->{repos};
    unless ($self->{auto}) {
	die "revision required" unless $self->{revspec};
	($fromrev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/
	    or die "revision must be N:M";
    }

    my $base_path = $src->{path};
    if ($self->{auto}) {
	($base_path, $fromrev, $torev) =
	    ($self->find_merge_base ($repos, $src->{path}, $dst->{path}), $repos->fs->youngest_rev);
	print "auto merge ($fromrev, $torev) $src->{path} -> $dst->{path} (base $base_path)\n";
	$cb_merged = sub { my ($editor, $baton, $pool) = @_;
			   $editor->change_dir_prop
			       ($baton, 'svk:merge',
				$self->get_new_ticket ($repos, $src->{path}, $dst->{path}));
		       } unless $self->{no_ticket};
    }

    unless ($dst->{copath} || defined $self->{message} || $self->{check_only}) {
	$self->{message} = get_buffer_from_editor
	    ('log message', $self->target_prompt,
	     ($self->{log} ?
	      $self->log_for_merge ($repos, $src->{path}, $fromrev+1, $torev) : '').
	     "\n".$self->target_prompt."\n", "svk-commitXXXXX");
    }

    # editor for the target
    my ($storage, %cb) = $self->get_editor ($dst);

    my $fs = $repos->fs;
    my $editor = SVK::MergeEditor->new
	( anchor => $src->{path},
	  base_anchor => $base_path,
	  base_root => $fs->revision_root ($fromrev),
	  target => '',
	  send_fulltext => $cb{mirror} ? 0 : 1,
	  cb_merged => $cb_merged,
	  storage => $storage,
	  %cb,
	);

    SVN::Repos::dir_delta ($fs->revision_root ($fromrev),
			   $base_path, '',
			   $fs->revision_root ($torev), $src->{path},
			   $editor, undef,
			   1, 1, 0, 1);

    # cleanup txn
    $cb{txn}->abort if $cb{txn};

    return;
}

sub log_for_merge {
    my $self = shift;
    my $buf = IO::String->new (\my $tmp);
    SVK::Command::Log::do_log (@_, 0, 0, 0, $buf);
    return $tmp;
}


sub find_merge_base {
    my ($self, $repos, $src, $dst) = @_;
    my $srcinfo = $self->find_merge_sources ($repos, $src);
    my $dstinfo = $self->find_merge_sources ($repos, $dst);
    my ($basepath, $baserev);

    for (grep {exists $srcinfo->{$_} && exists $dstinfo->{$_}} (keys %{{%$srcinfo,%$dstinfo}})) {
	my ($path) = m/:(.*)$/;
	my $rev = $srcinfo->{$_} < $dstinfo->{$_} ? $srcinfo->{$_} : $dstinfo->{$_};
	# XXX: shuold compare revprop svn:date instead, for old dead branch being newly synced back
	if (!$basepath || $rev > $baserev) {
	    ($basepath, $baserev) = ($path, $rev);
	}
    }
    return ($basepath, $baserev);
}

sub find_merge_sources {
    my ($self, $repos, $path, $verbatim, $noself) = @_;
    my $pool = SVN::Pool->new_default;

    my $fs = $repos->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);
    my $minfo = $root->node_prop ($path, 'svk:merge');
    my $myuuid = $fs->get_uuid ();
    if ($minfo) {
	$minfo = { map {my ($uuid, $path, $rev) = split ':', $_;
			my $m;
			($verbatim || ($uuid eq $myuuid)) ? ("$uuid:$path" => $rev) :
			    ($self->svn_mirror && ($m = SVN::Mirror::has_local ($repos, "$uuid:$path"))) ?
				("$myuuid:$m->{target_path}" => $m->find_local_rev ($rev)) : ()
			    } split ("\n", $minfo) };
    }
    if ($verbatim) {
	my ($uuid, $path, $rev) = $self->resolve_svm_source ($repos, $path);
	$minfo->{join(':', $uuid, $path)} = $rev
	    unless $noself;
	return $minfo;
    }
    else {
	$minfo->{join(':', $myuuid, $path)} = $fs->youngest_rev
	    unless $noself;
    }

    # XXX: follow the copy history provided by svm too
    my $spool = SVN::Pool->new_default ($pool);
    my $hist = $root->node_history ($path);
    while ($hist = $hist->prev (1)) {
	$spool->clear;
	my ($hpath, $rev) = $hist->location ();
	if ($hpath ne $path) {
	    my $source = join(':', $myuuid, $hpath);
	    $minfo->{$source} = $rev
		unless $minfo->{$source} && $minfo->{$source} > $rev;
	    last;
	}
    }

    return $minfo;
}

sub resolve_svm_source {
    my ($self, $repos, $path) = @_;
    my ($uuid, $rev, $m);
    my $mirrored;
    my $fs = $repos->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);

    if ($self->svn_mirror) {
	$m = eval 'SVN::Mirror::is_mirrored ($repos, $path)';
    }

    if ($m) {
	$uuid = $root->node_prop ($path, 'svm:uuid');
	$path = $m->{source};
	$path =~ s/^\Q$m->{source_root}\E//;
	$rev = $m->{fromrev};
    }
    else {
	($rev, $uuid) = ($fs->youngest_rev, $fs->get_uuid);
    }

    return ($uuid, $path, $rev);
}

sub get_new_ticket {
    my ($self, $repos, $src, $dst) = @_;

    my $srcinfo = $self->find_merge_sources ($repos, $src, 1);
    my $dstinfo = $self->find_merge_sources ($repos, $dst, 1);
    my ($uuid, $newinfo);

    # bring merge history up to date as from source
    ($uuid, $dst) = $self->resolve_svm_source ($repos, $dst);

    for (keys %{{%$srcinfo,%$dstinfo}}) {
	next if $_ eq "$uuid:$dst";
	no warnings 'uninitialized';
	$newinfo->{$_} = $srcinfo->{$_} > $dstinfo->{$_} ? $srcinfo->{$_} : $dstinfo->{$_};
	print "new merge ticket: $_:$newinfo->{$_}\n"
	    if !$dstinfo->{$_} || $newinfo->{$_} > $dstinfo->{$_};
    }

    return join ("\n", map {"$_:$newinfo->{$_}"} sort keys %$newinfo);
}

1;
