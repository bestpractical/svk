package SVK::Util;
use strict;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(md5 get_buffer_from_editor slurp_fh get_anchor get_prompt
		    find_svm_source resolve_svm_source svn_mirror);
our $VERSION   = '0.09';

use SVK::I18N;
use Digest::MD5 qw(md5_hex);
use File::Temp;
use Term::ReadLine;
my $svn_mirror = eval 'require SVN::Mirror; 1' ? 1 : 0;

sub svn_mirror { $svn_mirror }

my $tr;
sub get_prompt {
    my ($prompt, $regex) = @_;
    $tr ||= Term::ReadLine->new($0);

    {
	my $answer = $tr->readline("$prompt ");
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
	($fh, $file) = mkstemps ($file, '.tmp');
	print $fh $content;
	close $file;
    }
    else {
	open $fh, $file;
	local $/;
	$content = <$fh>;
    }

    while (1) {
	my $mtime = (stat($file))[9];
	my $editor =	defined($ENV{SVN_EDITOR}) ? $ENV{SVN_EDITOR}
	   		: defined($ENV{EDITOR}) ? $ENV{EDITOR}
			: "vi"; # fall back to something
	print loc("Waiting for editor...\n");
	system ($editor, $file) and die loc("Aborted.\n");
	last if (stat($file))[9] > $mtime;
	my $ans = get_prompt(
	    loc("%1 not modified: a)bort, e)dit, c)ommit?", $what),
	    qr/^[aec]/,
	);
	last if $ans =~ /^c/;
	die loc("Aborted.\n") if $ans =~ /^a/;
    }

    open $fh, $file;
    local $/;
    my @ret = defined $sep ? split (/\n\Q$sep\E\n/, <$fh>, 2) : (<$fh>);
    close $fh;
    unlink $file;
    return $ret[0] unless wantarray;

    my $old_targets = (split (/\n\Q$sep\E\n/, $content, 2))[1];
    my @new_targets = map [split(/\s+/, $_, 2)], grep /\S/, split(/\n+/, $ret[1]);
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
    my ($repos, $path) = @_;
    my ($uuid, $rev, $m, $mpath);
    my $mirrored;
    my $fs = $repos->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);

    if (svn_mirror) {
	($m, $mpath) = SVN::Mirror::is_mirrored ($repos, $path);
    }

    if ($m) {
	$path =~ s/\Q$mpath\E$//;
	$uuid = $root->node_prop ($path, 'svm:uuid');
	$path = $m->{source}.$mpath;
	$path =~ s/^\Q$m->{source_root}\E//;
	$rev = $m->{fromrev};
    }
    else {
	($rev, $uuid) = ($fs->youngest_rev, $fs->get_uuid);
    }

    return ($uuid, $path, $rev);
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

1;
