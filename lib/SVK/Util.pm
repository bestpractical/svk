package SVK::Util;
use strict;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(md5 get_buffer_from_editor slurp_fh get_anchor get_prompt
		    find_svm_source resolve_svm_source svn_mirror tmpfile
		    find_local_mirror abs_path mimetype mimetype_is_text);
our $VERSION = $SVK::VERSION;

use SVK::I18N;
use Digest::MD5 qw(md5_hex);
use File::Spec;
use Cwd;
use File::Temp 0.14 qw(mktemp);
# ra must be loaded earlier since it uses the default pool
use SVN::Core;
use SVN::Ra;

# loading svn::mirror on-the-fly causes output stream not respected,
# failing #1 in t/23commit. possibly because VCP calls select.
my $svn_mirror = eval 'require SVN::Mirror; 1' ? 1 : 0;
sub svn_mirror () {
    no warnings 'redefine';
    local $@;
    my $svn_mirror = eval { require SVN::Mirror; 1 };
    *svn_mirror = $svn_mirror ? sub () { 1 } : sub () { 0 };
    return $svn_mirror;
}

sub get_prompt {
    my ($prompt, $regex) = @_;
    local $|;
    $|++;

    {
	print "$prompt";
	my $answer = <STDIN>;
	chomp $answer;
	redo if $regex and $answer !~ $regex;
	return $answer;
    }
}

sub md5 {
    my $fh = shift;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

sub get_buffer_from_editor {
    my ($what, $sep, $content, $file, $anchor, $targets_ref) = @_;
    my $fh;
    if (defined $content) {
	($fh, $file) = tmpfile ($file, UNLINK => 0);
	print $fh $content;
	close $fh;
    }
    else {
	open $fh, $file or die $!;
	local $/;
	$content = <$fh>;
    }

    my $editor =	defined($ENV{SVN_EDITOR}) ? $ENV{SVN_EDITOR}
	   		: defined($ENV{EDITOR}) ? $ENV{EDITOR}
			: "vi"; # fall back to something
    my @editor = split (' ', $editor);
    while (1) {
	my $mtime = (stat($file))[9];
	print loc("Waiting for editor...\n");
	# XXX: check $?
	system (@editor, $file) and die loc("Aborted: %1\n", $!);
	last if (stat($file))[9] > $mtime;
	my $ans = get_prompt(
	    loc("%1 not modified: a)bort, e)dit, c)ommit?", $what),
	    qr/^[aec]/,
	);
	last if $ans =~ /^c/;
	die loc("Aborted.\n") if $ans =~ /^a/;
    }

    open $fh, $file or die $!;
    local $/;
    my @ret = defined $sep ? split (/\n\Q$sep\E\n/, <$fh>, 2) : (<$fh>);
    close $fh;
    unlink $file;
    return $ret[0] unless wantarray;

    # compare targets in commit message
    # XXX: test suites for this
    my $old_targets = (split (/\n\Q$sep\E\n/, $content, 2))[1];
    my @new_targets = map {s/^\s+//; # proponly change will have leading spacs
			   [split(/\s+/, $_, 2)]} grep /\S/, split(/\n+/, $ret[1]);
    if ($old_targets ne $ret[1]) {
	@$targets_ref = map $_->[1], @new_targets;
	s|^\Q$anchor\E/|| for @$targets_ref;
    }
    return ($ret[0], \@new_targets);
}

sub slurp_fh {
    my ($from, $to) = @_;
    local $/ = \16384;
    while (<$from>) {
	print $to $_;
    }
}

sub get_anchor {
    my $needtarget = shift;
    map {
	my (undef,$anchor,$target) = File::Spec->splitpath ($_);
	chop $anchor if length ($anchor) > 1;
	($anchor, $needtarget ? ($target) : ())
    } @_;
}

sub find_svm_source {
    my ($repos, $path, $rev) = @_;
    my $fs = $repos->fs;
    $rev ||= $fs->youngest_rev;
    my $root = $fs->revision_root ($rev);
    my ($uuid, $m, $mpath);

    if (svn_mirror) {
	($m, $mpath) = SVN::Mirror::is_mirrored ($repos, $path);
    }

    if ($m) {
	# XXX: we should normalize $rev before calling find_svm_source
	$rev = ($root->node_history($path)->prev(0)->location)[1]
	    unless $rev == $root->node_created_rev ($path);
	$rev = $m->find_remote_rev ($rev);
	$path =~ s/\Q$mpath\E$//;
	$uuid = $m->{source_uuid};
	$path = $m->{source}.$mpath;
	$path =~ s/^\Q$m->{source_root}\E//;
	$path ||= '/';
    }
    else {
	$uuid = $fs->get_uuid;
	$rev = ($root->node_history ($path)->prev (0)->location)[1];
    }

    return ($uuid, $path, $rev);
}

sub find_local_mirror {
    my ($repos, $uuid, $path, $rev) = @_;
    my $myuuid = $repos->fs->get_uuid;
    return unless svn_mirror && $uuid ne $myuuid;
    my ($m, $mpath) = SVN::Mirror::has_local ($repos, "$uuid:$path");
    return ("$m->{target_path}$mpath", $m->find_local_rev ($rev)) if $m;
}

sub resolve_svm_source {
    my ($repos, $uuid, $path) = @_;
    my $myuuid = $repos->fs->get_uuid;
    return ($path) if ($uuid eq $myuuid);
    return unless svn_mirror;
    my ($m, $mpath) = SVN::Mirror::has_local ($repos, "$uuid:$path");
    return unless $m;
    return ("$m->{target_path}$mpath", $m);
}

sub tmpfile {
    my ($temp, %args) = @_;
    my $dir = $ENV{TMPDIR} || '/tmp';
    $temp = "svk-${temp}XXXXX";
    return mktemp ("$dir/$temp") if exists $args{OPEN} && $args{OPEN} == 0;
    my $tmp = File::Temp->new ( TEMPLATE => $temp,
				DIR => $dir,
				SUFFIX => '.tmp',
				%args
			      );

    return wantarray ? ($tmp, $tmp->filename) : $tmp;
}


# return paths with components in symlink resolved, but keep the final
# path even if it's symlink

sub abs_path {
    my $path = shift;
    return Cwd::abs_path ($path) unless -l $path;
    my (undef, $dir, $pathname) = File::Spec->splitpath ($path);
    return File::Spec->catpath (undef, Cwd::abs_path ($dir), $pathname);
}

sub mimetype {
    no warnings 'redefine';
    local $@;
    my $mimetype = eval {
        require File::MimeInfo::Magic;
        \&File::MimeInfo::Magic::mimetype;
    };
    *mimetype = $mimetype ||= sub { undef };
    goto &$mimetype;
}

sub mimetype_is_text {
    my $type = shift;
    scalar $type =~ m{^(?:text/.*
                         |application/x-(?:perl
		                          |python
                                          |ruby
                                          |php
                                          |java
                                          |shellscript)
                         |image/x-x(?:bit|pix)map)$}xo;
}

1;
