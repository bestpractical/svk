package SVK::Util;
use strict;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
    IS_WIN32 DEFAULT_EDITOR TEXT_MODE HAS_SYMLINK HAS_SVN_MIRROR $EOL $SEP

    get_prompt get_buffer_from_editor edit_file

    get_encoding get_encoder from_native to_native

    find_local_mirror find_svm_source resolve_svm_source traverse_history
    find_prev_copy

    read_file write_file slurp_fh md5_fh bsd_glob mimetype mimetype_is_text

    abs_path abs2rel catdir catfile catpath devnull dirname get_anchor 
    move_path make_path splitpath splitdir tmpdir tmpfile get_depot_anchor
    catdepot

    is_symlink is_executable is_uri can_run
);
use SVK::Version;  our $VERSION = $SVK::VERSION;


use Config ();
use SVK::I18N;
use SVN::Core;
use SVN::Ra;
use autouse 'Encode'            => qw(resolve_alias decode encode);
use File::Glob qw(bsd_glob);
use autouse 'File::Basename' 	=> qw(dirname);
use autouse 'File::Spec::Functions' => 
                               qw(catdir catpath splitpath splitdir tmpdir);


=head1 NAME

SVK::Util - Utility functions for SVK classes

=head1 SYNOPSIS

    use SVK::Util qw( func1 func2 func3 )

=head1 DESCRIPTION

This is yet another abstraction function set for portable file, buffer and
IO handling, tailored to SVK's specific needs.

No symbols are exported by default; the user module needs to specify the
list of functions to import.


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
use constant HAS_SYMLINK => $Config::Config{d_symlink};

sub HAS_SVN_MIRROR () {
    no warnings 'redefine';
    local $@;
    my $has_svn_mirror = $ENV{SVKNOSVM} ? 0 : eval { require SVN::Mirror; 1 };
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

sub get_prompt { {
    my ($prompt, $pattern) = @_;

    local $| = 1;
    print $prompt;

    local *IN;
    local *SAVED = *STDIN;
    local *STDIN = *STDIN;

    my $formfeed = "";
    if (!-t STDIN and -r '/dev/tty' and open IN, '<', '/dev/tty') {
        *STDIN = *IN;
        $formfeed = "\r";
    }

    require Term::ReadKey;
    Term::ReadKey::ReadMode(IS_WIN32 ? 'normal' : 'raw');
    my $out = (IS_WIN32 ? sub { 1 } : sub { print @_ });

    my $answer = '';
    while (defined(my $key = Term::ReadKey::ReadKey(0))) {
        if ($key =~ /[\012\015]/) {
            $out->("\n") if $key eq $formfeed;
	    $out->($key); last;
        }
        elsif ($key eq "\cC") {
            Term::ReadKey::ReadMode('restore');
            *STDIN = *SAVED;
            Term::ReadKey::ReadMode('restore');
            my $msg = loc("Interrupted.\n");
            $msg =~ s{\n\z}{$formfeed\n};
            die $msg;
        }
        elsif ($key eq "\cH") {
            next unless length $answer;
            $out->("$key $key");
            chop $answer; next;
        }
        elsif ($key eq "\cW") {
            my $len = (length $answer) or next;
            $out->("\cH" x $len, " " x $len, "\cH" x $len);
            $answer = ''; next;
        }
        elsif (ord $key < 32) {
            # control character -- ignore it!
            next;
        }
        $out->($key);
        $answer .= $key;
    }

    if (defined $pattern) {
        $answer =~ $pattern or redo;
    }

    Term::ReadKey::ReadMode('restore');
    return $answer;
} }

=head3 edit_file ($file_name)

Launch editor to edit a file.

=cut

sub edit_file {
    my ($file) = @_;
    my $editor =	defined($ENV{SVN_EDITOR}) ? $ENV{SVN_EDITOR}
	   		: defined($ENV{EDITOR}) ? $ENV{EDITOR}
			: DEFAULT_EDITOR; # fall back to something
    my @editor = split (/ /, $editor);

    print loc("Waiting for editor...\n");

    # XXX: check $?
    system {$editor[0]} (@editor, $file) and die loc("Aborted: %1\n", $!);
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

    my $time = time;

    while (1) {
        open my $fh, '<', $file or die $!;
        my $md5 = md5_fh($fh);
        close $fh;

	edit_file ($file);

        open $fh, '<', $file or die $!;
        last if ($md5 ne md5_fh($fh));
        close $fh;

	my $ans = get_prompt(
	    loc("%1 not modified: a)bort, e)dit, c)ommit?", ucfirst($what)),
	    qr/^[aec]/,
	);
	last if $ans =~ /^c/;
	# XXX: save the file somewhere
	unlink ($file), die loc("Aborted.\n") if $ans =~ /^a/;
    }

    open $fh, $file or die $!;
    local $/;
    my @ret = defined $sep ? split (/\n\Q$sep\E\n/, <$fh>, 2) : (<$fh>);
    close $fh;
    unlink $file;

    die loc("Cannot find separator; aborted.\n")
        if defined($sep) and !defined($ret[1]);

    return $ret[0] unless wantarray;

    # Compare targets in commit message
    my $old_targets = (split (/\n\Q$sep\E\n/, $content, 2))[1];
    my @new_targets = map {s/^\s+//; # proponly change will have leading spacs
			   [split(/[\s\+]+/, $_, 2)]} grep /\S/, split(/\n+/, $ret[1]);
    if ($old_targets ne $ret[1]) {
        # Assign new targets 
	@$targets_ref = map abs2rel($_->[1], $anchor, undef, '/'), @new_targets;
    }
    return ($ret[0], \@new_targets);
}

=head3 get_encoding

Get the current encoding from locale

=cut

sub get_encoding {
    return 'utf8' if $^O eq 'darwin';
    local $@;
    return resolve_alias (eval {
	require Locale::Maketext::Lexicon;
        local $Locale::Maketext::Lexicon::Opts{encoding} = 'locale';
        Locale::Maketext::Lexicon::encoding();
    } || eval {
        require 'encoding.pm';
        defined &encoding::_get_locale_encoding() or die;
        return encoding::_get_locale_encoding();
    }) or 'utf8';
}

=head3 get_encoder ([$encoding])

=cut

sub get_encoder {
    my $enc = shift || get_encoding;
    return Encode::find_encoding ($enc);
}

=head3 from_native ($octets, $what, [$encoding])

=cut

sub from_native {
    my $enc = ref $_[2] ? $_[2] : get_encoder ($_[2]);
    my $buf = eval { $enc->decode ($_[0], 1) };
    die loc ("Can't decode %1 as %2.\n", $_[1], $enc->name) if $@;
    $_[0] = $buf;
    Encode::_utf8_off ($_[0]);
    return;
}

=head3 to_native ($octets, $what, [$encoding])

=cut

sub to_native {
    my $enc = ref $_[2] ? $_[2] : get_encoder ($_[2]);
    Encode::_utf8_on ($_[0]);
    my $buf = eval { $enc->encode ($_[0], 1) };
    die loc ("Can't encode %1 as %2.\n", $_[1], $enc->name) if $@;
    $_[0] = $buf;
    return;
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
    open my $fh, "< $_[0]" or die $!;
    return <$fh>;
}

=head3 write_file ($filename, $content)

Write out content to a file, overwriting existing content if present.

=cut

sub write_file {
    return print $_[1] if ($_[0] eq '-');
    open my $fh, '>', $_[0] or die $!;
    print $fh $_[1];
}

=head3 slurp_fh ($input_fh, $output_fh)

Read all data from the input filehandle and write them to the
output filehandle.  The input may also be a scalar, or reference
to a scalar.

=cut

sub slurp_fh {
    my $from = shift;
    my $to = shift;

    local $/ = \16384;

    if (!ref($from)) {
        print $to $from;
    }
    elsif (ref($from) eq 'SCALAR') {
        print $to $$from;
    }
    else {
        while (<$from>) {
            print $to $_;
        }
    }
}

=head3 md5_fh ($input_fh)

Calculate MD5 checksum for data in the input filehandle.

=cut

{
    no warnings 'once';
    push @EXPORT_OK, qw( md5 ); # deprecated compatibility API
    *md5 = *md5_fh;
}

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
    my $fh = shift;

    return 'text/plain' if -z $fh;

    binmode($fh);
    read $fh, my $data, 16*1024 or return undef;

    my $type = File::Type->checktype_contents($data);

    # On fallback, use the same logic as File::MimeInfo to detect text
    if ($type eq 'application/octet-stream') {
        substr($data, 0, 32) =~ m/[\x00-\x07\x0B\x0E-\x1A\x1C-\x1F]/
            or return 'text/plain';
    }

    return $type;
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
                                          |[kcz]?sh
                                          |awk
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

    if (!IS_WIN32) {
        require Cwd;
	return Cwd::abs_path ($path) unless -l $path;
	my (undef, $dir, $pathname) = splitpath ($path);
	return catpath (undef, Cwd::abs_path ($dir), $pathname);
    }

    # Win32 - Complex handling to get the correct base case
    $path = '.' if !length $path;
    $path = ucfirst(Win32::GetFullPathName($path));
    return undef unless -d dirname($path);

    my ($base, $remainder) = ($path, '');
    while (length($base) > 1) {
	my $new_base = Win32::GetLongPathName($base);
	return $new_base.$remainder if defined $new_base;

	$new_base = dirname($base);
	$remainder = substr($base, length($new_base)) . $remainder;
	$base = $new_base;
    }

    return undef;
}

=head3 abs2rel ($pathname, $old_basedir, $new_basedir, $sep)

Replace the base directory in the native pathname to another base directory
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

    if ($rel =~ /(?:\A|\Q$SEP\E)\.\.(?:\Q$SEP\E|\z)/o) {
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
	(grep {defined and length} @_), splitdir($pathname)
    )
}

=head3 catpath ($volume, $directory, $filename)

XXX Undocumented - See File::Spec

=head3 devnull ()

Return a file name suitable for reading, and guaranteed to be empty.

=cut

my $devnull;
sub devnull () {
    IS_WIN32 ? ($devnull ||= tmpfile('', UNLINK => 1))
             : File::Spec::Functions::devnull();
}

=head3 get_anchor ($need_target, @paths)

Returns the (anchor, target) pairs for native path @paths.  Discard
the targets being returned unless $need_target.

=cut

sub get_anchor {
    my $need_target = shift;
    map {
	my ($volume, $anchor, $target) = splitpath ($_);
	chop $anchor if length ($anchor) > 1;
	($volume.$anchor, $need_target ? ($target) : ())
    } @_;
}

=head3 get_depot_anchor ($need_target, @paths)

Returns the (anchor, target) pairs for depotpaths @paths.  Discard the
targets being returned unless $need_target.

=cut

sub get_depot_anchor {
    my $need_target = shift;
    map {
	my (undef, $anchor, $target) = File::Spec::Unix->splitpath ($_);
	chop $anchor if length ($anchor) > 1;
	($anchor, $need_target ? ($target) : ())
    } @_;
}

=head3 catdepot ($depot_name, @paths)

=cut

sub catdepot {
    return File::Spec::Unix->catdir('/', @_);
}

=head3 make_path ($path)

Create a directory, and intermediate directories as required.  

=cut

sub make_path {
    my $path = shift;

    return undef if !defined($path) or -d $path;

    require File::Path;
    return File::Path::mkpath([$path]);
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

    require File::Temp;
    return File::Temp::mktemp ("$dir/$temp") if exists $args{OPEN} && $args{OPEN} == 0;
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
    require ExtUtils::MakeMaker;
    defined($_[0]) and length($_[0]) and MM->maybe_command($_[0]);
}

=head3 can_run ($filename)

Check if we can run some command.

=cut

sub can_run {
    my ($_cmd, @path) = @_;

    return $_cmd if (-x $_cmd or $_cmd = is_executable($_cmd));

    for my $dir ((split /$Config::Config{path_sep}/, $ENV{PATH}), @path, '.') {
        my $abs = catfile($dir, $_[0]);
        return $abs if (-x $abs or $abs = is_executable($abs));
    }

    return;
}

=head3 is_uri ($string)

Check if a string is a valid URI.

=cut

sub is_uri {
    ($_[0] =~ /^[A-Za-z][-+.A-Za-z0-9]+:/)
}

=head3 move_path ($source, $target)

Move a path to another place, creating intermediate directories in the target
path if neccessary.  If move failed, tell the user to move it manually.

=cut

sub move_path {
    my ($source, $target) = @_;

    if (-d $source and (!-d $target or rmdir($target))) {
        require File::Copy;
        make_path (dirname($target));
        File::Copy::move ($source => $target) and return;
    }

    print loc(
        "Cannot rename %1 to %2; please move it manually.\n",
        catfile($source), catfile($target),
    );
}

sub traverse_history {
    my %args = @_;

    my $old_pool = SVN::Pool->new;
    my $new_pool = SVN::Pool->new;
    my $spool = SVN::Pool->new_default;

    my $hist = $args{root}->node_history ($args{path}, $old_pool);
    my $rv;

    while ($hist = $hist->prev(($args{cross} || 0), $new_pool)) {
        $rv = $args{callback}->($hist->location ($new_pool));
        last if !$rv;
        $old_pool->clear;
	$spool->clear;
        ($old_pool, $new_pool) = ($new_pool, $old_pool);
    }

    return $rv;
}

=head3 find_prev_copy ($fs, $rev)

Find the revision of the nearest copy in a repository that is less or
equal to C<$rev>.  Returns the found revision number, and a hash of
arrayref that contains copied paths and its source found in that
revision.

=cut

sub _copies_in_root {
    my ($root) = @_;
    my $copies;
    my $changed = $root->paths_changed;
    for (keys %$changed) {
	next if $changed->{$_}->change_kind == $SVN::Fs::PathChange::delete;
	my ($copyfrom_rev, $copyfrom_path) = $root->copied_from ($_);
	$copies->{$_} = [$copyfrom_rev, $copyfrom_path]
	    if defined $copyfrom_path;
    }
    return $copies;
}

sub find_prev_copy {
    my ($fs, $endrev, $ppool) = @_;
    my $pool = SVN::Pool->new_default;
    # hold this resulting root in the subpool of ppool.
    my $spool = $ppool ? SVN::Pool::create ($$ppool) : $pool;
    my ($rev, $startrev) = ($endrev, $endrev);
    my ($root, $copy);
    while ($rev > 0) {
	$pool->clear;
	SVN::Pool::apr_pool_clear ($spool) if $ppool;
	if (defined (my $cache = $fs->revision_prop ($rev, 'svk:copy_cache_prev'))) {
	    $startrev = $rev + 1;
	    $rev = $cache;
	    last if $rev == 0;
	}
	$root = $fs->revision_root ($rev, $spool);
	if ($copy = _copies_in_root ($root)) {
	    last;
	}
	--$rev; --$startrev;
    }
    $fs->change_rev_prop ($_, 'svk:copy_cache_prev', $rev), $pool->clear
	for $startrev..$endrev;
    return unless $rev;
    return ($root, $copy);
}

1;

__END__

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
