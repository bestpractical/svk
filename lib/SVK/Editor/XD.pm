package SVK::Editor::XD;
use strict;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVN::Delta::Editor);
use SVK::I18N;
use SVN::Delta;
use File::Path;
use SVK::Util qw( get_anchor md5_fh );

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

The target path of the editor calls.  Used only for path reporting translation.

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

=back

=cut

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
}

sub open_root {
    my ($self, $base_revision) = @_;
    $self->{baserev} = $base_revision;
    return '';
}

sub add_file {
    my ($self, $path, $pdir) = @_;
    my $copath = $path;
    $self->{added}{$path} = 1;
    $self->{get_copath}($copath);
    die loc("path %1 already exists", $path)
	if !$self->{added}{$pdir} && (-l $copath || -e _);
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 does not exist", $path) unless -l $copath || -e _;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    my $base;
    return if $self->{check_only};
    my ($copath, $dpath) = ($path, $path);
    $self->{get_copath}($copath);
    $self->{get_path}($dpath);
    unless ($self->{added}{$path}) {
	my ($dir,$file) = get_anchor (1, $copath);
	my $basename = "$dir.svk.$file.base";

	rename ($copath, $basename)
	  or die loc("rename %1 to %2 failed: %3", $copath, $basename, $!);

	$base = SVK::XD::get_fh ($self->{oldroot}, '<', $dpath, $basename);
	if (!$self->{ignore_checksum} && $checksum) {
	    my $md5 = md5_fh ($base);
	    die loc("source checksum mismatch") if $md5 ne $checksum;
	    seek $base, 0, 0;
	}

	$self->{base}{$path} = [$base, $basename,
				-l $basename ? () : [stat($base)]];
    }
    # XXX: should test merge to co with keywords
    delete $self->{props}{$path}{'svn:keywords'} unless $self->{update};
    my $fh = SVK::XD::get_fh ($self->{newroot}, '>', $dpath, $copath,
			      $self->{added}{$path} ? $self->{props}{$path} || {}: undef)
	or warn "can't open $path";

    # The fh is refed by the current default pool, not the pool here
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty($pool),
				 $fh, undef, undef, $pool)];
}

sub close_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    if ((my $base = $self->{base}{$path})) {
	close $base->[0];
	unlink $base->[1];
	chmod $base->[2][2], $copath if $base->[2];
	delete $self->{base}{$path};
    }
    elsif (!$self->{update} && !$self->{check_only}) {
	$self->{xd}{checkout}->store_fast ($copath, { '.schedule' => 'add' });
    }
    if ($self->{update}) {
	# XXX: use store_fast with new data::hierarchy release.
	$self->{xd}{checkout}->store_fast ($copath, {revision => $self->{revision}});
	$self->{xd}->fix_permission ($copath, $self->{exe}{$path})
	    if exists $self->{exe}{$path};
    }
    delete $self->{props}{$path};
    delete $self->{added}{$path};
}

sub add_directory {
    my ($self, $path, $pdir) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 already exists", $copath) if !$self->{added}{$pdir} && -e $copath;
    mkdir ($copath) unless $self->{check_only};
    $self->{xd}{checkout}->store_fast ($copath, { '.schedule' => 'add' })
	if !$self->{update} && !$self->{check_only};
    $self->{added}{$path} = 1;
    return $path;
}

sub open_directory {
    my ($self, $path) = @_;
    # XXX: test if directory exists
    return $path;
}

sub delete_entry {
    my ($self, $path, $revision) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    $self->{get_path}($path);
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

sub close_directory {
    my ($self, $path) = @_;
    return if $self->{target} && !$path;
    my $copath = $path;
    $self->{get_copath}($copath);
    $self->{xd}{checkout}->store_recursively ($copath,
					      {revision => $self->{revision},
					       '.deleted' => undef})
	if $self->{update};
    delete $self->{added}{$path};
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
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
    $self->close_directory('');
}

sub abort_edit {
    my ($self) = @_;
    $self->close_directory('');
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
