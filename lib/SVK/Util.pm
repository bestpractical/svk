package SVK::Util;
require Exporter;
@ISA       = qw(Exporter);
@EXPORT_OK = qw(md5 get_buffer_from_editor slurp_fh get_anchor get_prompt);
$VERSION   = '0.09';

use Digest::MD5 qw(md5_hex);
use File::Temp;
use Term::ReadLine;

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
	print "waiting for editor...\n";
	system ($editor, $file) and die "Aborted";
	last if (stat($file))[9] > $mtime;
	my $ans = get_prompt(
	    "$what not modified: a)bort, e)dit, c)ommit?",
	    qr/^[aec]/,
	);
	last if $ans =~ /^c/;
	die "aborted.\n" if $ans =~ /^a/;
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


1;
