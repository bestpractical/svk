package SVK::Util;
use strict;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(md5 get_buffer_from_editor slurp_fh get_anchor get_prompt
		    find_svm_source resolve_svm_source svn_mirror tmpfile
		    find_local_mirror abs_path mimetype mimetype_is_text
		    abs2rel catfile catdir catpath splitpath splitdir tmpdir
		    devnull is_symlink is_executable $SEP $EOL %Config
		    HAS_SYMLINK IS_WIN32 TEXT_MODE DEFAULT_EDITOR);
our $VERSION = $SVK::VERSION;

use Config;
use SVK::I18N;
use Digest::MD5;
use Cwd;
use File::Temp 0.14 qw(mktemp);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir catpath splitpath splitdir tmpdir );
# ra must be loaded earlier since it uses the default pool
use SVN::Core;
use SVN::Ra;

use constant HAS_SYMLINK => $Config{d_symlink};
use constant IS_WIN32 => ($^O eq 'MSWin32');
use constant TEXT_MODE => IS_WIN32 ? ':crlf' : '';
use constant DEFAULT_EDITOR => IS_WIN32 ? 'notepad.exe' : 'vi';

our $SEP = catdir('');
our $EOL = IS_WIN32 ? "\015\012" : "\012";

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
	($fh, $file) = tmpfile ($file, TEXT => 1, UNLINK => 0);
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
			: DEFAULT_EDITOR; # fall back to something
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
			   [split(/[\s\+]+/, $_, 2)]} grep /\S/, split(/\n+/, $ret[1]);
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
	my ($volume,$anchor,$target) = splitpath ($_);
	chop $anchor if length ($anchor) > 1;
	($volume.$anchor, $needtarget ? ($target) : ())
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
	$path = $m->{source_path}.$mpath;
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
    return ("$m->{target_path}$mpath",
	    $rev ? $m->find_local_rev ($rev) : $rev) if $m;
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
    my $dir = tmpdir;
    my $text = delete $args{TEXT};
    $temp = "svk-${temp}XXXXX";
    return mktemp ("$dir/$temp") if exists $args{OPEN} && $args{OPEN} == 0;
    my $tmp = File::Temp->new ( TEMPLATE => $temp,
				DIR => $dir,
				SUFFIX => '.tmp',
				%args
			      );
    binmode($tmp, TEXT_MODE) if $text;
    return wantarray ? ($tmp, $tmp->filename) : $tmp;
}


# return paths with components in symlink resolved, but keep the final
# path even if it's symlink

sub abs_path {
    my $path = shift;
    if (defined &Win32::GetFullPathName) {
	$path = '.' if !length $path;
	$path = Win32::GetFullPathName($path);
	return((-d dirname($path)) ? $path : undef);
    }
    return Cwd::abs_path ($path) unless -l $path;
    my (undef, $dir, $pathname) = splitpath ($path);
    return catpath (undef, Cwd::abs_path ($dir), $pathname);
}

sub mimetype {
    no strict 'refs';
    no warnings 'redefine';

    local $@;
    my $mimetype = eval {
        require File::MimeInfo::Magic;
        \&File::MimeInfo::Magic::mimetype;
    } || sub { undef };

    *{caller().'::mimetype'} = $mimetype;
    *mimetype = $mimetype;

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

sub abs2rel {
    my ($child, $parent, $new_parent, $slash) = @_;
    if (IS_WIN32 and $child =~ /^\W/) {
	print STDERR "*********Called: $child <=> $parent\n";
	exit;
    }
    my $rel = File::Spec::Functions::abs2rel($child, $parent);
    if (index($rel, '..') > -1) {
        $rel = $child;
    }
    elsif (defined $new_parent) {
        $rel = catdir($new_parent, $rel);
    }
    $rel =~ s/\Q$SEP/$slash/g if $slash and $SEP ne $slash;
    return $rel;
}

sub catfile {
    return File::Spec::Functions::catfile (
	grep {defined and length} map splitdir($_), @_
    )
}

sub devnull () {
    IS_WIN32 ? tmpfile('', UNLINK => 1) : File::Spec::Functions::devnull();
}

sub is_symlink {
    HAS_SYMLINK ? @_ ? (-l $_[0]) : (-l _) : 0;
}

sub is_executable {
    IS_WIN32 ? @_ ? (-f $_[0]) : (-f _)
	     : @_ ? (-x $_[0]) : (-x _);
}

1;
