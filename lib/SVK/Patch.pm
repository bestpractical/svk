package SVK::Patch;
use strict;
our $VERSION = $SVK::VERSION;

=head1 NAME

SVK::Patch - Class representing a patch to be applied

=head1 SYNOPSIS

 # Using SVK::Patch
 $patch = SVK::Patch->load ($file, $xd, $depotname);
 $patch->view;
 # update patch for target
 $patch->update;
 # regenerate patch from source branch
 $patch->regen;

 # apply the patch to designated target
 $patch->apply ($check_only);
 # apply to arbitrary target
 $patch->apply_to ($target, $storage, %cb);

 # Creating SVK::Patch
 $patch = SVK::Patch->new ('my patch', $xd, $depotname, $src, $dst);
 $editor = $patch->editor
 # feed things to $editor
 $patch->store ($file);

=head1 DESCRIPTION

SVK::Patch represents tree delta and assorted meta data, such as merge
info and anchor for the patch to be applied.

=cut

use SVK::Editor::Patch;
use SVK::Util qw(find_svm_source find_local_mirror resolve_svm_source);
use SVK::Merge;
use SVK::Editor::Diff;
use SVK::Target::Universal;
use Storable qw/nfreeze thaw/;
use MIME::Base64;
use Compress::Zlib;

=head1 METHODS

=head2 new

Create a SVK::Patch object.

=cut

sub new {
    my ($class, $name, $xd, $depotname, $src, $dst) = @_;
    my $self = bless { name   => $name,
		       level  => 0,
		       _xd    => $xd,
		       _depot => $depotname,
		       _source => $src,
		       _target => $dst }, $class;
    (undef, undef, $self->{_repos}) = $self->{_xd}->find_repos ("/$self->{_depot}/", 1);
    $self->{source} = $self->{_source}->universal;
    $self->{target} = $self->{_target}->universal;
    return $self;
}

=head2 load

Load a SVK::Patch object from file.

=cut

sub load {
    my ($class, $file, $xd, $depot) = @_;
    open FH, '<', $file or die $!;
    local $/;
    my $self = thaw (uncompress (decode_base64(<FH>)));
    $self->{_xd} = $xd;
    $self->{_depot} = $depot;
    for (qw/source target/) {
	my $tmp = $self->{"_$_"} = $self->{$_}->local ($xd, $depot) or next;
	$tmp = $tmp->new (revision => undef);
	$tmp->normalize;
	$self->{"_${_}_updated"} = 1
	    if $tmp->{revision} > $self->{"_$_"}->{revision};
    }
    (undef, undef, $self->{_repos}) = $self->{_xd}->find_repos ("/$self->{_depot}/", 1);
    return $self;
}

=head2 store

Store a SVK::Patch object to file.

=cut

sub store {
    my ($self, $file) = @_;
    my $store = bless {map {m/^_/ ? () : ($_ => $self->{$_})} keys %$self}, ref ($self);
    open FH, '>', $file or die $!;
    print FH encode_base64(compress (nfreeze ($store)));
}

=head2 editor

Return the SVK::Editor::Patch object for feeding editor calls to, or
driving other editors.

=cut

sub editor {
    my ($self) = @_;
    $self->{editor} ||= SVK::Editor::Patch->new;
}

sub _path_attribute_text {
    my ($self, $type) = @_;
    # XXX: check if source / target is updated
    my ($local, $mirrored, $updated);
    if (my $target = $self->{"_$type"}) {
	if ($target->{repos}->fs->get_uuid eq $self->{$type}{uuid}) {
	    ++$local;
	}
	else {
	    ++$mirrored;
	}
    }
    return ($local ? ' [local]' : '').($mirrored ? ' [mirrored]' : '').
	($self->{"_${type}_updated"} ? ' [updated]' : '');
}

sub view {
    my ($self) = @_;
    my $fs = $self->{_repos}->fs;
    print "=== Patch <$self->{name}> level $self->{level}\n";
    print "Source: ".join(':', @{$self->{source}}{qw/uuid path rev/}).
	$self->_path_attribute_text ('source')."\n";
    print "Target: ".join(':', @{$self->{target}}{qw/uuid path rev/}).
	$self->_path_attribute_text ('target')."\n";
    print "Log:\n".$self->{log}."\n";

    die "Target not local nor mirrored, unable to view patch."
	unless $self->{_target};

    my $baseroot = $self->{_target}->root;
    my $anchor = $self->{_target}->path;
    $self->editor->drive
	( SVK::Editor::Diff->new
	  ( cb_basecontent => sub { my ($path) = @_;
				    my $base = $baseroot->file_contents ("$anchor/$path");
				    return $base;
				},
	    cb_baseprop => sub { my ($path, $pname) = @_;
				 return $baseroot->node_prop ("$anchor/$path", $pname);
			     },
	    llabel => "revision $self->{target}{rev}",
	    rlabel => "patch $self->{name} level $self->{level}",
	    external => $ENV{SVKDIFF},
	  ));
}

sub apply {
    my ($self, $check_only) = @_;
    my $commit = SVK::Command->get_cmd ('commit', $self->{_xd});
    my $target = $self->{_target};
    $commit->{message} = "Apply $self->{name}\@$self->{level}";
    $commit->{check_only} = $check_only;
    $self->apply_to ($target, $commit->get_editor ($target));
}

sub apply_to {
    my ($self, $target, $storage, %cb) = @_;
    my $base = $self->{_target}
	or die "Target not local nor mirrored, unable to test patch.";
    # XXX: cb_merged
    my $editor = SVK::Editor::Merge->new
	( base_anchor => $base->path,
	  base_root => $base->root,
	  send_fulltext => 0,
	  storage => $storage,
	  anchor => $target->path,
	  target => '',
	  send_fulltext => !$cb{patch} && !$cb{mirror},
	  %cb,
	);
    $self->{editor}->drive ($editor);
    return $editor->{conflicts};
}

# XXX: update and regen are identify.  the only difference is soruce or target to be updated
sub update {
    my ($self) = @_;
    die "Target not local nor mirrored, unable to update patch."
	unless $self->{_target};

    return unless $self->{_target_updated};
    my $target = $self->{_target}->new (revision => undef);
    $target->normalize;
    my $patch = SVK::Editor::Patch->new;
    my $conflict;

    if ($conflict = $self->apply_to ($target, $patch, patch => 1,
				     SVK::Editor::Merge::cb_for_root
				     ($target->root, $target->path, $target->{revision}))) {

	print "Conflicts.\n";
	return $conflict;
    }

    $self->{_target} = $target;
    $self->{target} = $target->universal;
    $self->{editor} = $patch;
    return 0;
}

sub regen {
    my ($self) = @_;
    my $target = $self->{_target}
	or die "Target not local nor mirrored, unable to regen patch.";
    unless ($self->{level} == 0 || $self->{_source_updated}) {
	print "Source of path <$self->{name}> not updated or not local. No need to update.\n";
	return;
    }
    my $source = $self->{_source}->new (revision => undef);
    $source->normalize;
    my $merge = SVK::Merge->auto (repos => $self->{_repos},
				  src => $source,
				  dst => $target);
    my $conflict;
    my $patch = SVK::Editor::Patch->new;
    # XXX: handle empty
    unless ($conflict = $merge->run ($patch,
				     SVK::Editor::Merge::cb_for_root
				     ($target->root, $target->path, $target->{revision}))) {
	$self->{log} = $merge->log;
	++$self->{level};
	$self->{_source} = $source;
	$self->{source} = $source->universal;
	$self->{editor} = $patch;
    }
    return $conflict;
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
