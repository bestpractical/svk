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

sub find_repos {
    my ($self, $depotpath) = @_;

    my ($depot, $path) = $depotpath =~ m|^/(\w*)/(.*)/?$|;

    die "non-default depot name not supported yet" if $depot;

    my $repospath = $self->{depotmap}{$depot} or die "no such depot: $depot";

    return ($repospath, $path);
}

sub _do_update {
    my ($self, $rev, $copath) = @_;
    my ($depotpath, $startrev) = @{$self->{checkoutmap}{$copath}};
    my ($repos, $path) = $self->find_repos ($depotpath);

    my $r = SVN::Repos::open ($repos) or die "can't open repos $repos";
    my $fs = $r->fs;
    $rev = $fs->youngest_rev if $rev eq 'HEAD';

    warn "syncing $depotpath($path) to $copath from $startrev to $rev";
    my (undef,$anchor,$target) = File::Spec->splitpath ($path);
    chop $anchor;
    SVN::Repos::dir_delta ($fs->revision_root ($startrev), $anchor, $target,
			   $fs->revision_root ($rev), $path,
			   SVN::XD::UpdateEditor->new(_debug=>0),
#			   SVN::Delta::Editor->new(_debug=>1),
			   1, 1, 0, 1);
    $self->{checkoutmap}{$copath}[1] = $rev;
}

sub update {
    my ($self, $path, $rev) = @_;
    $path = File::Spec->rel2abs ($path);
    $rev ||= 'HEAD';
    warn "updating $path";
    $self->_do_update ($rev, $path);
}

sub checkout {
    my ($self, $depotpath, $rev, $copath) = @_;
    my ($repos, $path) = $self->find_repos ($depotpath);
    die "don't know where to checkot"  unless $copath || $path;
    $copath = File::Spec->rel2abs ($copath ||
				   (File::Spec->splitdir($path))[-1]);

    die "checkout path $copath already exists" if -e $copath;

    mkdir ($copath);
    # XXX: status keeping
    $self->{checkoutmap}{$copath} = [$depotpath,0];
    $rev ||= 'HEAD';

    $self->_do_update($rev, $copath)
}

use File::Find;
use Text::Diff ();

sub diff {
    my ($self, $xdpath) = @_;
    $xdpath = File::Spec->rel2abs ($xdpath);
    my ($depotpath, $rev) = @{$self->{checkoutmap}{$xdpath}};
    my ($repos, $path) = $self->find_repos ($depotpath);

    my $r = SVN::Repos::open ($repos) or die "can't open repos $repos";
    my $fs = $r->fs;
    my $root = $fs->revision_root ($rev);

    find(sub {
	     my $cpath = $File::Find::name;
	     return if -d $cpath;
	     $cpath =~ s|^$xdpath/|$path/|;
	     my $kind = $root->check_path ($cpath);
	     if ($kind == $SVN::Node::none) {
		 print "? $File::Find::name\n";
		 return;
	     }
	     warn "file modified"
		 if md5file($File::Find::name) ne
		     $root->file_md5_checksum ($cpath);
	  }, $xdpath);

}

sub status {
    my ($self, $path) = @_;

    my ($repos, $stpath) = $self->find_repos ($path);
}

sub md5file {
    my $fname = shift;
    open my $fh, '<', $fname;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
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
    warn "trying to delete $path\@$revision\n";
    rmtree ([$path]);
    $self->{info}{$path}{status} = ['D'];
}

sub close_edit {
    my ($self) = @_;
    print "finishing update\n";
}


1;
