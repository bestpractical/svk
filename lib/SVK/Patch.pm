package SVK::Patch;
use strict;
our $VERSION = '0.15';

=head1 NAME

SVK::Patch - Class representing a patch to be applied

=head1 SYNOPSIS

    $patch = SVK::Patch->new (name => 'my patch', level => 0);
    $patch->applyto ($repos, $target);
    $patch->from ($repos, $source);

    $editor = $patch->editor
    # feed things to $editor
    $patch->view
    $patch->applicable

=head1 DESCRIPTION

SVK::Patch represents tree delta and assorted meta data, such as merge
info and anchor for the patch to be applied.

=cut

use SVK::Editor::Patch;
use SVK::Util qw(find_svm_source find_local_mirror resolve_svm_source);
use SVK::Merge;
use SVK::Editor::Diff;
use Storable qw/nfreeze thaw/;
use MIME::Base64;
use Compress::Zlib;

=head1 METHODS

=head2 new

Create a SVK::Patch object.

=cut

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, $class;
    %$self = @arg;
    return $self;
}

=head2 load

Load a SVK::Patch object from file.

=cut

sub load {
    my ($class, $file, $repos) = @_;
    open FH, '<', $file or die $!;
    local $/;
    my $self = thaw (uncompress (decode_base64(<FH>)));
    $self->{_repos} = $repos;
    $self->_resolve_path ('source', $repos);
    $self->_resolve_path ('target', $repos);
    return $self;
}

=head2 store

Store a SVK::Patch object to file.

=cut

sub store {
    my ($self, $file) = @_;
    # XXX: shouldn't alter self when store
    delete $self->{$_}
	for grep {m/^_/} keys %$self;
    open FH, '>', $file;
    print FH encode_base64(compress (nfreeze ($self)));
}

=head2 editor

Return the SVK::Editor::Patch object for feeding editor calls to, or
driving other editors.

=cut

sub editor {
    my ($self) = @_;
    $self->{editor} ||= SVK::Editor::Patch->new;
}

sub _patch_path {
    my ($self, $type, $path, $repos) = @_;
    @{$self}{map {"${type}_$_"} qw/uuid path rev/} = find_svm_source ($repos, $path);
}

sub _resolve_path {
    my ($self, $type, $repos) = @_;
    my ($local, $path, $rev);
    if ($self->{"${type}_uuid"} ne $repos->fs->get_uuid) {
	($path, $rev) = @{$self}{map {"_${type}_$_"} qw/path rev/} =
	    find_local_mirror ($repos, @{$self}{map {"${type}_$_"} qw/uuid path rev/});
    }
    else {
	$local = $self->{"_${type}_local"} = 1;
    }
    if ($local || $path) {
	($path, $rev) = @{$self}{map {"${type}_$_"} qw/path rev/} if $local;
	my $fs = $repos->fs;
	my $nrev = ($fs->revision_root ($fs->youngest_rev)->
		node_history ($path)->prev (0)->location)[1];
	$self->{"_${type}_updated"} = 1
	    if $nrev > $rev;
    }
}

=head2 applyto

Assign the destination ($repos, $path) of the patch.

=cut

sub applyto {
    my ($self, $path, $repos) = @_;
    $repos ||= $self->{_repos};
    $self->_patch_path ('target', $path, $repos);
    $self->_resolve_path ('target', $repos);
}

=head2 from

Assign the source ($repos, $path) of the patch.

=cut

sub from {
    my ($self, $path, $repos) = @_;
    $repos ||= $self->{_repos};
    $self->_patch_path ('source', $path, $repos);
    $self->_resolve_path ('source', $repos);
}

sub _path_attribute_text {
    my ($self, $type) = @_;
    my ($local, $path, $updated) = @{$self}{map {"_${type}_$_"} qw/local path updated/};
    return ($local ? ' [local]' : '').($path ? ' [mirrored]' : '').
	($updated ? ' [updated]' : '');
}

sub view {
    my ($self, $repos) = @_;
    $repos ||= $self->{_repos};
    my $fs = $repos->fs;
    print "=== Patch <$self->{name}> level $self->{level}\n";
    print "Source: ".join(':', @{$self}{qw/source_uuid source_path source_rev/}).
	$self->_path_attribute_text ('source')."\n";
    print "Target: ".join(':', @{$self}{qw/target_uuid target_path target_rev/}).
	$self->_path_attribute_text ('target')."\n";
    print "Log:\n".$self->{log}."\n";

    die "Target not local nor mirrored, unable to view patch."
	unless $self->{_target_local} || $self->{_target_path};

    my ($anchor, $mrev) = $self->{_target_local} ? @{$self}{qw/target_path target_rev/} :
	@{$self}{qw/_target_path _target_rev/};
    my $baseroot = $fs->revision_root ($mrev);
    $self->editor->drive
	( SVK::Editor::Diff->new
	  ( cb_basecontent => sub { my ($path) = @_;
				    my $base = $baseroot->file_contents ("$anchor/$path");
				    return $base;
				},
	    cb_baseprop => sub { my ($path, $pname) = @_;
				 return $baseroot->node_prop ("$anchor/$path", $pname);
			     },
	    llabel => "revision $self->{target_rev}",
	    rlabel => "patch $self->{name} level $self->{level}",
	    external => $ENV{SVKDIFF},
	  ));
}

sub applicable {
    my ($self, $repos) = @_;
    # XXX: support testing with other path
    $repos ||= $self->{_repos};
    die "Target not local nor mirrored, unable to test patch."
	unless $self->{_target_local} || $self->{_target_path};
    my ($anchor, $mrev) = $self->{_target_local} ? @{$self}{qw/target_path target_rev/} :
	@{$self}{qw/_target_path _target_rev/};

    my $fs = $repos->fs;
    unless ($self->{_target_updated}) {
	print "Target of patch <$self->{name}> not updated. No need to test.\n";
#	return;
    }

    my $yrev = $fs->youngest_rev;
    my ($base_path, $baserev) = @{$self}{qw/target_path target_rev/};
    my $editor = SVK::Editor::Merge->new
	( anchor => $anchor,
	  base_anchor => $anchor,
	  base_root => $fs->revision_root ($mrev),
	  target => '',
	  send_fulltext => 0,
	  storage => SVN::Delta::Editor->new,
	  SVK::Editor::Merge::cb_for_root ($fs->revision_root ($yrev), $anchor, $yrev),
	);
    $self->{editor}->drive ($editor);
    return $editor->{conflicts};
}

sub update {
    my ($self, $merge, $repos) = @_;
    $repos ||= $self->{_repos};
    die "Target not local nor mirrored, unable to update patch."
	unless $self->{_target_local} || $self->{_target_path};
    my ($anchor, $mrev) = $self->{_target_local} ? @{$self}{qw/target_path target_rev/} :
	@{$self}{qw/_target_path _target_rev/};
    my $fs = $repos->fs;
    unless ($self->{_source_updated}) {
	print "Source of path <$self->{name}> not updated or not local. No need to update.\n";
#	return;
    }

    my $yrev = $fs->youngest_rev;
    my ($base_path, $baserev, $fromrev, $torev) =
	($merge->find_merge_base ($repos, $self->{source_path}, $anchor), $yrev);
    $self->{log} = $merge->log ($repos, $self->{source_path}, $fromrev+1, $torev);
    my $editor = SVK::Editor::Merge->new
	( anchor => $self->{source_path},
	  base_anchor => $base_path,
	  base_root => $fs->revision_root ($baserev),
	  target => '',
	  send_fulltext => 0,
	  storage => $self->editor,
	  SVK::Editor::Merge::cb_for_root ($fs->revision_root ($yrev), $anchor, $yrev),
	);
    SVN::Repos::dir_delta ($fs->revision_root ($baserev),
			   $base_path, '',
			   $fs->revision_root ($torev), $self->{source_path},
			   $editor, undef,
			   1, 1, 0, 1);
    ++$self->{level};
    return $editor->{conflicts};
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
