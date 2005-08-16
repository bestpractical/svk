package SVK::Editor::XD;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);
use SVK::I18N;
use autouse 'File::Path' => qw(rmtree);
use autouse 'SVK::Util'  => qw( get_anchor md5_fh catpath );

=head1 NAME

SVK::Editor::XD - An editor for modifying checkout copies

=head1 SYNOPSIS

$editor = SVK::Editor::XD->new
    ( path => $path,
      target => $target,
      oldroot => $fs->revision_root ($fromrev),
      newroot => $fs->revision_root ($torev),
      xd => $xd,
      get_copath => sub { ... },
    );


=head1 DESCRIPTION

SVK::Editor::XD modifies existing checkout copies at the paths
translated by the get_copath callback, according to the incoming
editor calls.

There are two modes, one is for applying changes to checkout copy as
external modification, like merging changes. The other is update mode,
which is used for bringing changes from depot to checkout copies.

=head1 PARAMETERS

=over

=item path

The anchor of the editor calls.

=item target

The target path of the editor calls.  Used for deciding if the root's
meta data needs to be updated in update mode.

=item xd

XD object.

=item oldroot

Old root before the editor calls.

=item newroot

New root after the editor calls.

=item update

Working in update mode.

=item get_copath

A callback to translate paths in editor calls to copath.

=item report

Path for reporting modifications.

=item ignore_checksum

Don't do checksum verification.

=item ignore_keywords

Don't do keyword translations.

=back

=cut

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
}

sub open_root {
    my ($self, $base_revision) = @_;
    $self->{baserev} = $base_revision;
    $self->{signature} ||= SVK::XD::Signature->new (root => $self->{xd}->cache_directory)
	if $self->{update};
    return $self->open_directory ('', '');
}

sub add_file {
    my ($self, $path, $pdir) = @_;
    return unless defined $pdir;
    my $copath = $path;
    $self->{added}{$path} = 1;
    $self->{get_copath}($copath);
    die loc("path %1 already exists", $path)
	if !$self->{added}{$pdir} && (-l $copath || -e _);
    return $path;
}

sub open_file {
    my ($self, $path, $pdir) = @_;
    return unless defined $pdir;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 does not exist", $path) unless -l $copath || -e _;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    return unless defined $path;
    return if $self->{check_only};
    my ($copath, $spath, $dpath, $base) = ($path, $path, $path);
    $self->{get_copath}->($copath);
    $self->{get_store_path}->($spath);
    $self->{get_path}->($dpath);
    unless ($self->{added}{$path}) {
	my ($dir,$file) = get_anchor (1, $copath);
	my $basename = catpath (undef, $dir, ".svk.$file.base");

	rename ($copath, $basename) or return undef;
	$base = SVK::XD::get_fh ($self->{oldroot}, '<', $dpath, $basename) or return undef;
	if (!$self->{ignore_checksum} && $checksum) {
	    my $md5 = md5_fh ($base);
	    die loc("source checksum mismatch") if $md5 ne $checksum;
	    seek $base, 0, 0;
	}

	$self->{base}{$path} = [$base, $basename,
				-l $basename ? () : [stat($base)]];
    }
    # XXX: should test merge to co with keywords
    delete $self->{props}{$path}{'svn:keywords'}
	if !$self->{update} or $self->{ignore_keywords};
    my $fh = SVK::XD::get_fh ($self->{newroot}, '>', $spath, $copath,
			      $self->{added}{$path} ? $self->{props}{$path} || {}: undef)
	or return undef;
    # The fh is refed by the current default pool, not the pool here
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty($pool),
				 $fh, undef, undef, $pool)];
}

sub close_file {
    my ($self, $path) = @_;
    return unless defined $path;
    my $copath = $path;
    $self->{get_copath}($copath);
    if ((my $base = $self->{base}{$path})) {
	close $base->[0];
	unlink $base->[1];
	chmod $base->[2][2], $copath if $base->[2];
	delete $self->{base}{$path};
    }
    elsif (!$self->{update} && !$self->{check_only}) {
	$self->_schedule_entry($copath);
    }
    if ($self->{update}) {
	my (undef, $file) = get_anchor (1, $copath);
	# populate signature cache for added files only, because
	# modified file might be edited from merge editor, and thus
	# actually unclean.  There should be notification from merge
	# editor in the future, or to update the cache in cb_localmod
	# for modified entries.
	$self->{cursignature}[-1]->changed ($file)
	    if $self->{added}{$path};
	$self->{xd}{checkout}->store_fast ($copath, {revision => $self->{revision}});
	$self->{xd}->fix_permission ($copath, $self->{exe}{$path})
	    if exists $self->{exe}{$path};
    }
    delete $self->{props}{$path};
    delete $self->{added}{$path};
}

sub add_directory {
    my ($self, $path, $pdir) = @_;
    return undef unless defined $pdir;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 already exists", $copath) if !$self->{added}{$pdir} && -e $copath;
    unless ($self->{check_only}) {
	unless (mkdir ($copath)) {
	    # XXX: note this entry and make the resulting checkout map
	    # retain the entry for this path
	    return undef;
	}
    }
    if (!$self->{update} && !$self->{check_only}) {
	$self->_schedule_entry($copath);
    }
    $self->{added}{$path} = 1;
    push @{$self->{cursignature}}, $self->{signature}->load ($copath)
	if $self->{update};
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir) = @_;
    return undef unless defined $pdir;
    # XXX: test if directory exists
    if ($self->{update}) {
	my $copath = $path;
	$self->{get_copath}->($copath);
	push @{$self->{cursignature}}, $self->{signature}->load ($copath);
	$self->{cursignature}[-1]{keepold} = 1;
    }
    return $path;
}

sub delete_entry {
    my ($self, $path, $revision, $pdir) = @_;
    return unless defined $pdir;
    my $copath = $path;
    $self->{get_copath}($copath);
    return if $self->{check_only};
    if ($self->{update}) {
	-d $copath ? rmtree ([$copath]) : unlink($copath);
    }
    else {
	$self->{get_path}($path);
	$self->{xd}->do_delete (%$self,
				path => $path,
				copath => $copath,
				quiet => 1);
    }
}

sub close_directory {
    my ($self, $path) = @_;
    return unless defined $path;
    return if $self->{target} && !length ($path);
    my $copath = $path;
    $self->{get_copath}($copath);
    if ($self->{update}) {
	# XXX: handle unwritable entries and back them up after the store
	$self->{xd}{checkout}->store_recursively ($copath,
						  {revision => $self->{revision},
						   '.deleted' => undef});
	if (@{$self->{cursignature}}) {
	    $self->{cursignature}[-1]->flush;
	    pop @{$self->{cursignature}};
	}
    }

    delete $self->{added}{$path};
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    return unless defined $path;
    $self->{props}{$path}{$name} = $value
	if $self->{added}{$path};
    return if $self->{check_only};
    my $copath = $path;
    $self->{get_copath}($copath);
    if ($self->{update}) {
	$self->{exe}{$path} = $value
	    if $name eq 'svn:executable';
    }
    else {
	$self->{xd}->do_propset ( quiet => 1,
				  copath => $copath,
				  propname => $name,
				  propvalue => $value,
				);
    }
}

sub change_dir_prop {
    my ($self, @arg) = @_;
    $self->change_file_prop (@arg);
}

sub close_edit {
    my ($self) = @_;
}

sub abort_edit {
    my ($self) = @_;
}

sub _schedule_entry {
    my ($self, $copath) = @_;
    my (undef, $schedule) = $self->{xd}->get_entry($copath);
    $self->{xd}{checkout}->store_fast
	($copath, { '.schedule' => $schedule ? 'replace' : 'add' });
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
