package SVK::Editor::XD;
use strict;
our $VERSION = $SVK::VERSION;
use base qw(SVK::Editor::Checkout);
use SVK::I18N;
use SVK::Util qw( get_anchor md5_fh );

=head1 NAME

SVK::Editor::XD - An editor for modifying svk checkout copies

=head1 SYNOPSIS

$editor = SVK::Editor::XD->new
    ( path => $path,
      target => $target,
      oldroot => $fs->revision_root ($fromrev),
      newroot => $fs->revision_root ($torev),
      xd => $xd,
      get_copath => sub { ... },
      get_path => sub { ... },
    );


=head1 DESCRIPTION

SVK::Editor::XD modifies existing checkout copies at the paths
translated by the get_copath callback, according to the incoming
editor calls.  The path in the depot is translated with the get_path
callback.

There are two modes, one is for applying changes to checkout copy as
external modification, like merging changes. The other is update mode,
which is used for bringing changes from depot to checkout copies.

=head1 PARAMETERS

In addition to the paramters to L<SVK::Editor::Checkout>:

=over

=item target

The target path of the editor calls.

=item xd

XD object.

=item oldroot

Old root before the editor calls.

=item newroot

New root after the editor calls.

=item update

Working in update mode.

=item get_path

A callback to translate paths in editor calls to path in depot.

=back

=cut

sub get_base {
    my ($self, $path, $copath, $checksum) = @_;
    my $dpath = $path;
    $self->{get_path}->($dpath);

    my ($dir,$file) = get_anchor (1, $copath);
    my $basename = "$dir.svk.$file.base";

    rename ($copath, $basename)
	or die loc("rename %1 to %2 failed: %3", $copath, $basename, $!);

    my $base = SVK::XD::get_fh ($self->{oldroot}, '<', $dpath, $basename);
    if (!$self->{ignore_checksum} && $checksum) {
	my $md5 = md5_fh ($base);
	die loc("source checksum mismatch") if $md5 ne $checksum;
	seek $base, 0, 0;
    }

    return [$base, $basename, -l $basename ? () : [stat($base)]];
}

sub get_fh {
    my ($self, $path, $copath) = @_;
    my $dpath = $path;
    $self->{get_path}->($dpath);
    # XXX: should test merge to co with keywords
    delete $self->{props}{$path}{'svn:keywords'} unless $self->{update};
    my $fh = SVK::XD::get_fh ($self->{newroot}, '>', $dpath, $copath,
			      $self->{added}{$path} ? $self->{props}{$path} || {}: undef)
	or warn "can't open $path";
    return $fh;
}

sub close_file {
    my $self = shift;
    $self->SUPER::close_file (@_);
    my $path = shift;
    my $copath = $path;
    $self->{get_copath}($copath);
    if ($self->{update}) {
	$self->{xd}{checkout}->store_fast ($copath, {revision => $self->{revision}});
	$self->{xd}->fix_permission ($copath, $self->{exe}{$path})
	    if exists $self->{exe}{$path};
    }
    else {
	$self->{xd}{checkout}->store_fast ($copath, { '.schedule' => 'add' })
	    if !$self->{base}{$path} &&  !$self->{check_only};
    }
    delete $self->{props}{$path};
    delete $self->{added}{$path};
}

sub add_directory {
    my $self = shift;
    my ($path) = @_;
    $self->SUPER::add_directory (@_);
    my $copath = $path;
    $self->{get_copath}($copath);
    $self->{xd}{checkout}->store_fast ($copath, { '.schedule' => 'add' })
	if !$self->{update} && !$self->{check_only};
    $self->{added}{$path} = 1;
    return $path;
}

sub do_delete {
    my $self = shift;
    return $self->SUPER::do_delete (@_)
	if $self->{update};

    my ($path, $copath) = @_;
    $self->{get_path}($path);
    $self->{xd}->do_delete (%$self,
			    path => $path,
			    copath => $copath,
			    quiet => 1);
}

sub close_directory {
    my ($self, $path) = @_;
    # the root is just an anchor
    return if $self->{target} && $path eq '';
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
}

sub abort_edit {
    my ($self) = @_;
    $self->close_directory('');
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
