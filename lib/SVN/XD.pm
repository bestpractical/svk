package SVN::XD;
use strict;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
require SVN::Delta;
use File::Spec;
use YAML;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}


sub do_update {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;

    warn "syncing $arg{depotpath}($arg{path}) to $arg{copath} from $arg{startrev} to $arg{rev}";
    my (undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
    chop $anchor;
    SVN::Repos::dir_delta ($fs->revision_root ($arg{startrev}), $anchor, $target,
			   $fs->revision_root ($arg{rev}), $arg{path},
			   SVN::XD::UpdateEditor->new(_debug=>0),
#			   SVN::Delta::Editor->new(_debug=>1),
			   1, 1, 0, 1);
}

package TreeData;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}

package SVN::XD::UpdateEditor;
require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);
use File::Path;
use Digest::MD5;

sub md5 {
    my $fh = shift;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{baserev} = $baserev;
    return '';
}

sub add_file {
    my ($self, $path) = @_;
    $self->{info}{$path}{status} = (-e $path ? undef : ['A']);
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    $self->{info}{$path}{status} = (-e $path ? [] : undef);
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum) = @_;
    return unless $self->{info}{$path}{status};
    my ($fh, $base);
    unless ($self->{info}{$path}{status}[0]) {
	my (undef,$dir,$file) = File::Spec->splitpath ($path);
	open $base, '<', $path;

	if ($checksum) {
	    my $md5 = md5($base);
	    if ($checksum ne $md5) {
		warn "base checksum mismatch for $path, should do merge";
		warn "$checksum vs $md5\n";
		close $base;
		undef $self->{info}{$path}{status};
		return undef;
#		$self->{info}{$path}{status}[0] = 'G';
	    }
	    seek $base, 0, 0;
	}
	$self->{info}{$path}{status}[0] = 'U';

	my $basename = "$dir.svk.$file.base";
	rename ($path, $basename);
	$self->{info}{$path}{base} = [$base, $basename];

    }
    open $fh, '>', $path or warn "can't open $path";
    $self->{info}{$path}{fh} = $fh;
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty(),
				 $fh, undef, undef)];
}

sub close_file {
    my ($self, $path, $checksum) = @_;
    my $info = $self->{info}{$path};
    no warnings 'uninitialized';
    # let close_directory reports about its children
    if ($info->{status}) {
	print sprintf ("%1s%1s \%s\n",$info->{status}[0],
		       $info->{status}[1], $path);
    }
    else {
	print "   $path - skipped\n";
    }
    if ($info->{base}) {
	close $info->{base}[0];
	unlink $info->{base}[1];
    }
    close $info->{fh};
    undef $self->{info}{$path};
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

sub close_directory {
    my ($self, $path) = @_;
    print ".  $path\n";
}


sub delete_entry {
    my ($self, $path, $revision) = @_;
    # check if everyone under $path is sane for delete";
    rmtree ([$path]);
    $self->{info}{$path}{status} = ['D'];
}

sub close_edit {
    my ($self) = @_;
    print "finishing update\n";
}


1;
