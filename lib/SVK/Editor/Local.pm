package SVK::Editor::Local;
use strict;
use SVK::Editor::XD;
use SVK::Util qw (get_anchor md5);
use SVK::I18N;
use File::Path;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVK::Editor::XD);

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    my $base;

    my ($copath, $dpath) = ($path, $path);
    $self->{get_copath}($copath);
    unless ($self->{added}{$path}) {
	my ($dir,$file) = get_anchor (1, $copath);
	my $basename = "$dir.svk.$file.base";
	open $base, '<', $copath or die $!;
	if ($checksum) {
	    my $md5 = md5($base);
	    die loc("source checksum mismatch") if $md5 ne $checksum;
	    seek $base, 0, 0;
	}
	rename ($copath, $basename);
	$self->{base}{$path} = [$base, $basename,
				-l $basename ? () : [stat($base)]];
    }
    open my $fh, '>', $copath or warn "can't open $path: $!";

    # The fh is refed by the current default pool, not the pool here
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty($pool),
				 $fh, undef, undef, $pool)];
}

sub delete_entry {
    my ($self, $path, $revision) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    # XXX: check if everyone under $path is sane for delete";
    return if $self->{check_only};
    if ($self->{update}) {
	-d $copath ? rmtree ([$copath]) : unlink($copath);
    }
    else {
	$self->{xd}->do_delete (%$self,
				path => $path,
				copath => $copath,
				quiet => 1);
    }
}

1;
