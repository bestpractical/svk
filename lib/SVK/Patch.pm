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
use SVK::Util qw(find_svm_source resolve_svm_source);
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
    my ($class, $file) = @_;
    open FH, '<', $file or die $!;
    local $/;
    return thaw (uncompress (decode_base64(<FH>)));
}

=head2 store

Store a SVK::Patch object to file.

=cut

sub store {
    my ($self, $file) = @_;
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
    my ($self, $repos, $type, $path) = @_;
    @{$self}{map {"${type}_$_"} qw/uuid path rev/} = find_svm_source ($repos, $path);
}

=head2 applyto

Assign the destination ($repos, $path) of the patch.

=cut

sub applyto {
    my ($self, $repos, $path) = @_;
    $self->_patch_path ($repos, 'target', $path);
}

=head2 from

Assign the source ($repos, $path) of the patch.

=cut

sub from {
    my ($self, $repos, $path) = @_;
    $self->_patch_path ($repos, 'source', $path);
}

sub _path_attribute {
    my ($self, $fs, $uuid, $path, $rev) = @_;
    my $mirror;
    my $local = $self->local ($fs, $uuid);
#    if (!$local) {
#	$mirror = 
#    }
    my $updated = ($local &&
		   ($fs->revision_root ($fs->youngest_rev)->
		    node_history ($path)->prev (0)->location)[1] > $rev);
    return ($local, $updated);
}

sub _path_attribute_text {
    my $self = shift;
    my ($local, $updated) = $self->_path_attribute (@_);
    return ($local ? ' [local]' : '').($updated ? ' [updated]' : '');
}

sub local {
    my ($self, $fs, $uuid) = @_;
    return ($uuid eq $fs->get_uuid);
}

sub local_mirror {
    my ($self, $repos) = @_;
    my ($anchor, $m) = resolve_svm_source ($repos, @{$self}{qw/target_uuid target_path/});
    return unless $anchor;
    return ($anchor, $m ? $m->find_local_rev ($self->{target_rev}) : $self->{target_rev}, $m);
}

sub view {
    my ($self, $repos) = @_;
    my $fs = $repos->fs;
    print "=== Patch <$self->{name}> level $self->{level}\n";
    my ($anchor, $mrev, $mirrored) = $self->local_mirror ($repos)
	or die "Target not local nor mirrored, unable to view patch.\n";

    my @source = @{$self}{qw/source_uuid source_path source_rev/};
    print "Source: ".join(':', @source).$self->_path_attribute_text ($fs, @source)."\n";

    print "Target: ".join(':', @{$self}{qw/target_uuid target_path target_rev/}).
	$self->_path_attribute_text ($fs, $mirrored ? $self->{source_uuid} : $self->{target_uuid},
				     $anchor, $mrev)."\n";
    print "Log:\n".$self->{log}."\n";
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
    my ($anchor, $mrev) = $self->local_mirror ($repos)
	or die "Target not local nor mirrored, unable to test patch.\n";

    my $fs = $repos->fs;
    my (undef, $updated) = $self->_path_attribute ($fs, $self->{source_uuid}, $anchor, $mrev);
    unless ($updated) {
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
    my ($self, $repos, $merge) = @_;
    my ($anchor, $mrev) = $self->local_mirror ($repos)
	or die "Target not local nor mirrored, unable to update patch.\n";
    my $fs = $repos->fs;
    my ($local, $updated) = $self->_path_attribute ($fs, @{$self}{qw/source_uuid source_path source_rev/});
    unless ($local) {
	print "Source of path <$self->{name}> not updated or not local. No need to update.\n";
	return;
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
