package SVK::Util;
use strict;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
    IS_WIN32 DEFAULT_EDITOR TEXT_MODE HAS_SYMLINK HAS_SVN_MIRROR $EOL $SEP

    get_prompt get_buffer_from_editor

    find_local_mirror find_svm_source resolve_svm_source 

    read_file write_file slurp_fh md5_fh mimetype mimetype_is_text

    abs_path abs2rel catdir catfile catpath devnull get_anchor 
    splitpath splitdir tmpdir tmpfile 

    is_symlink is_executable
);
our $VERSION = $SVK::VERSION;

=head1 NAME

SVK::Util - Utility functions for SVK classes

=head1 SYNOPSIS

    use SVK::Util qw( func1 func2 func3 )

=head1 DESCRIPTION

This is yet another abstraction function set for portable file, buffer and
IO handling, tailored to SVK's specific needs.

No symbols are exported by default; the user module needs to specify the
list of functions to import.

=cut

use Config;
use SVK::I18N;
use Digest::MD5;
use Cwd;
use File::Temp 0.14 qw(mktemp);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir catpath splitpath splitdir tmpdir );
use ExtUtils::MakeMaker ();
# ra must be loaded earlier since it uses the default pool
use SVN::Core;
use SVN::Ra;

=head1 CONSTANTS

=head2 Constant Functions

=head3 IS_WIN32

Boolean flag to indicate whether this system is running Microsoft Windows.

=head3 DEFAULT_EDITOR

The default program to invoke for editing buffers: C<notepad.exe> on Win32,
C<vi> otherwise.

=head3 TEXT_MODE

The I/O layer for text files: C<:crlf> on Win32, empty otherwise.

=head3 HAS_SYMLINK

Boolean flag to indicate whether this system supports C<symlink()>.

=head3 HAS_SVN_MIRROR

Boolean flag to indicate whether we can successfully load L<SVN::Mirror>.

=head2 Constant Scalars

=head3 $SEP

Native path separator: platform: C<\> on dosish platforms, C</> otherwise.

=head3 $EOL

End of line marker: C<\015\012> on Win32, C<\012> otherwise.

=cut

use constant IS_WIN32 => ($^O eq 'MSWin32');
use constant TEXT_MODE => IS_WIN32 ? ':crlf' : '';
use constant DEFAULT_EDITOR => IS_WIN32 ? 'notepad.exe' : 'vi';
use constant HAS_SYMLINK => $Config{d_symlink};

sub HAS_SVN_MIRROR () {
    no warnings 'redefine';
    local $@;
    my $has_svn_mirror = eval { require SVN::Mirror; 1 };
    *HAS_SVN_MIRROR = $has_svn_mirror ? sub () { 1 } : sub () { 0 };
    return $has_svn_mirror;
}

our $SEP = catdir('');
our $EOL = IS_WIN32 ? "\015\012" : "\012";

=head1 FUNCTIONS

=head2 User Interactivity

=head3 get_prompt ($prompt, $pattern)

Repeatedly prompt the user for a line of answer, until it matches 
the regular expression pattern.  Returns the chomped answer line.

=cut

sub get_prompt {
    my ($prompt, $pattern) = @_;

    local $| = 1;
    {
	print "$prompt";
	my $answer = <STDIN>;
	chomp $answer;
	if (defined $pattern) {
	    $answer =~ $pattern or redo;
	}
	return $answer;
    }
}

=head3 get_buffer_from_editor ($what, $sep, $content, $filename, $anchor, $targets_ref)

XXX Undocumented

=cut

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
	    loc("%1 not modified: a)bort, e)dit, c)ommit?", ucfirst($what)),
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

=head2 Mirror Handling

=head3 find_local_mirror ($repos, $uuid, $path, $rev)

XXX Undocumented

=cut

sub find_local_mirror {
    my ($repos, $uuid, $path, $rev) = @_;
    my $myuuid = $repos->fs->get_uuid;
    return unless HAS_SVN_MIRROR && $uuid ne $myuuid;
    my ($m, $mpath) = SVN::Mirror::has_local ($repos, "$uuid:$path");
    return ("$m->{target_path}$mpath",
	    $rev ? $m->find_local_rev ($rev) : $rev) if $m;
}

=head3 find_svm_source ($repos, $path, $rev)

XXX Undocumented

=cut

sub find_svm_source {
    my ($repos, $path, $rev) = @_;
    my $fs = $repos->fs;
    $rev ||= $fs->youngest_rev;
    my $root = $fs->revision_root ($rev);
    my ($uuid, $m, $mpath);

    if (HAS_SVN_MIRROR) {
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

=head3 resolve_svm_source ($repos, $uuid, $path)

XXX Undocumented

=cut

sub resolve_svm_source {
    my ($repos, $uuid, $path) = @_;
    my $myuuid = $repos->fs->get_uuid;
    return ($path) if ($uuid eq $myuuid);
    return unless HAS_SVN_MIRROR;
    my ($m, $mpath) = SVN::Mirror::has_local ($repos, "$uuid:$path");
    return unless $m;
    return ("$m->{target_path}$mpath", $m);
}

=head2 File Content Manipulation

=head3 read_file ($filename)

Read from a file and returns its content as a single scalar.

=cut

sub read_file {
    local $/;
    open my $fh, '<', $_[0] or die $!;
    return <$fh>;
}

=head3 write_file ($filename, $content)

Write out content to a file, overwriting existing content if present.

=cut

sub write_file {
    open my $fh, '>', $_[0] or die $!;
    print $fh $_[1];
}

=head3 slurp_fh ($input_fh, $output_fh)

Read all data from the input filehandle and write them to the
output filehandle.

=cut

sub slurp_fh {
    my ($from, $to) = @_;
    local $/ = \16384;
    while (<$from>) {
	print $to $_;
    }
}

=head3 md5_fh ($input_fh)

Calculate MD5 checksum for data in the input filehandle.

=cut

push @EXPORT_OK, qw( md5 ); # deprecated compatibility API
*md5 = *md5_fh;

sub md5_fh {
    my $fh = shift;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

=head3 mimetype ($file)

Return the MIME type for the file, or C<undef> if the MIME database
is missing on the system.

=cut

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

=head3 mimetype_is_text ($mimetype)

Return whether a MIME type string looks like a text file.

=cut


sub mimetype_is_text {
    my $type = shift;
    scalar $type =~ m{^(?:text/.*
                         |application/x-(?:perl
		                          |python
                                          |ruby
                                          |php
                                          |java
                                          |shellscript)
                         |image/x-x(?:bit|pix)map)$}x;
}

=head2 Path and Filename Handling

=head3 abspath ($path)

Return paths with components in symlink resolved, but keep the final
path even if it's symlink.  Returns C<undef> if the base directory
does not exist.

=cut

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

=head3 abs2rel ($pathname, $old_basedir, $new_basedir, $sep)

Replace the base directory in the pathname to another base directory
and return the result.

If the pathname is not under C<$old_basedir>, it is not unmodified.

If C<$new_basedir> is an empty string, removes the old base directory but
keeps the trailing slash.  If C<$new_basedir> is C<undef>, also removes
the trailing slash.

By default, the return value of this function will use C<$SEP> as its
path separator.  Setting C<$sep> to C</> will turn native path separators
into C</> instead.

=cut

sub abs2rel {
    my ($pathname, $old_basedir, $new_basedir, $sep) = @_;

    my $rel = File::Spec::Functions::abs2rel($pathname, $old_basedir);

    if (index($rel, '..') > -1) {
        $rel = $pathname;
    }
    elsif (defined $new_basedir) {
        $rel = catdir($new_basedir, $rel);
    }

    $rel =~ s/\Q$SEP/$sep/go if $sep and $SEP ne $sep;
    return $rel;
}

=head3 catdir (@directories)

Concatenate directory names to form a complete path; also removes the
trailing slash from the resulting string, unless it is the root directory.

=head3 catfile (@directories, $pathname)

Concatenate one or more directory names and a filename to form a complete
path, ending with a filename.  If C<$pathname> contains directories, they
will be splitted off to the end of C<@directories>.

=cut

sub catfile {
    my $pathname = pop;
    return File::Spec::Functions::catfile (
	grep {defined and length} @_, splitdir($pathname)
    )
}

=head3 catpath ($volume, $directory, $filename)

XXX Undocumented - See File::Spec

=head3 devnull ()

Return a file name suitable for reading, and guaranteed to be empty.

=cut

sub devnull () {
    IS_WIN32 ? tmpfile('', UNLINK => 1) : File::Spec::Functions::devnull();
}

=head3 get_anchor ($need_target)

XXX Undocumented

=cut

sub get_anchor {
    my $need_target = shift;
    map {
	my ($volume, $anchor, $target) = splitpath ($_);
	chop $anchor if length ($anchor) > 1;
	($volume.$anchor, $need_target ? ($target) : ())
    } @_;
}

=head3 splitpath ($path)

Splits a path in to volume, directory, and filename portions.  On systems
with no concept of volume, returns an empty string for volume.

=head3 splitdir ($path)

The opposite of C<catdir()>; return a list of path components.

=head3 tmpdir ()

Return the name of the first writable directory from a list of possible
temporary directories.

=head3 tmpfile (TEXT => $is_textmode, %args)

In scalar context, return the filehandle of a temporary file.
In list context, return the filehandle and the filename.

If C<$is_textmode> is true, the returned file handle is marked with
C<TEXT_MODE>.

See L<File::Temp> for valid keys of C<%args>.

=cut

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

=head3 is_symlink ($filename)

Return whether a file is a symbolic link, as determined by C<-l>.
If C<$filename> is not specified, return C<-l _> instead.

=cut

sub is_symlink {
    HAS_SYMLINK ? @_ ? (-l $_[0]) : (-l _) : 0;
}

=head3 is_executable ($filename)

Return whether a file is likely to be an executable file.
Unlike C<is_symlink()>, the C<$filename> argument is not optional.

=cut

sub is_executable {
    MM->maybe_command($_[0]);
}

1;

__END__

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
