package SVK::Editor::Checkout;
use strict;
our $VERSION = $SVK::VERSION;
use base 'SVK::Editor';
use SVK::I18N;
use SVN::Delta;
use File::Path;
use SVK::Util qw( get_anchor md5_fh catpath );
use IO::Digest;

=head1 NAME

SVK::Editor::File - An editor for modifying files on filesystems

=head1 SYNOPSIS

$editor = SVK::Editor::Checkout->new
    ( path => $path,
      get_copath => sub { ... },
    );


=head1 DESCRIPTION

SVK::Editor::Checkout modifies existing checkouts at the paths
translated by the get_copath callback, according to the incoming
editor calls.

=head1 PARAMETERS

=over

=item path

The anchor of the editor calls.

=item get_copath

A callback to translate paths in editor calls to copath.

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

sub get_fh {
    my ($self, $path, $copath) = @_;
    open my $fh, '>', $copath or warn "can't open $path: $!", return;
    $self->{iod}{$path} = IO::Digest->new ($fh, 'MD5')
	unless $self->{ignore_checksum};
    return $fh;
}

sub get_base {
    my ($self, $path, $copath, $checksum) = @_;
    return unless defined $path;
    my ($dir,$file) = get_anchor (1, $copath);
    my $basename = catpath (undef, $dir, ".svk.$file.base");
    rename ($copath, $basename)
	or die loc("rename %1 to %2 failed: %3", $copath, $basename, $!);

    open my $base, '<', $basename or die $!;
    if (!$self->{ignore_checksum} && $checksum) {
	my $md5 = md5_fh ($base);
	if ($md5 ne $checksum) {
	    close $base;
	    rename $basename, $copath;
	    return $self->{cb_base_checksum}->($path)
		if $self->{cb_base_checksum};
	    die loc("source checksum mismatch")
	}
	seek $base, 0, 0;
    }

    return [$base, $basename, -l $basename ? () : [stat($base)]];
}

sub close_base {
    my ($self, $base) = @_;
    close $base->[0];
    unlink $base->[1];
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    return unless defined $path;
    return if $self->{check_only};
    my ($copath, $dpath) = ($path, $path);
    $self->{get_copath}($copath);
    my $base;
    unless ($self->{added}{$path}) {
	$self->{base}{$path} = $self->get_base ($path, $copath, $checksum)
	    or return undef;
	$base = $self->{base}{$path}[0];
    }

    my $fh = $self->get_fh ($path, $copath) or return undef;

    # The fh is refed by the current default pool, not the pool here
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty($pool),
				 $fh, undef, undef, $pool)];
}

sub close_file {
    my ($self, $path, $checksum) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("result checksum mismatch")
	if $self->{iod}{$path} && $self->{iod}{$path}->hexdigest ne $checksum;

    if ((my $base = $self->{base}{$path})) {
	chmod $base->[2][2], $copath if $base->[2];
	$self->close_base ($base);
	delete $self->{base}{$path};
    }
    delete $self->{iod}{$path};
    delete $self->{added}{$path};
}

sub add_directory {
    my ($self, $path, $pdir) = @_;
    return unless defined $pdir;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 already exists", $copath) if !$self->{added}{$pdir} && -e $copath;
    mkdir ($copath) or return undef
	unless $self->{check_only};
    $self->{added}{$path} = 1;
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir) = @_;
    return undef unless defined $pdir;
    # XXX: test if directory exists
    return $path;
}

sub do_delete {
    my ($self, $path, $copath) = @_;
    -d $copath ? rmtree ([$copath]) : unlink($copath);
}

sub delete_entry {
    my ($self, $path, $revision, $pdir) = @_;
    return unless defined $pdir;
    return if $self->{check_only};
    my $copath = $path;
    $self->{get_copath}($copath);
    $self->do_delete ($path, $copath);
}

sub close_directory {
    my ($self, $path) = @_;
    return unless defined $path;
    delete $self->{added}{$path};
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    # cache props when add
    $self->{props}{$path}{$name} = $value
	if $self->{added}{$path};
    return if $self->{check_only};
}

sub change_dir_prop {
    my ($self, @arg) = @_;
    $self->change_file_prop (@arg);
}

sub close_edit {
    my ($self) = @_;
#    $self->close_directory('');
}

sub abort_edit {
    my ($self) = @_;
    # XXX: check this
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
