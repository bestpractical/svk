package SVK::CombineEditor;
use strict;
use File::Temp;
use SVN::Simple::Edit;

our $VERSION = '0.08';
our @ISA = qw(SVN::Delta::Editor);

=head1 NAME

SVK::CombineEditor - An editor combining several editor calls to one

=head1 SYNOPSIS

$editor = SVK::CombineEditor->new
    ( base_root => $fs->revision_root ($rev),
      storage => $storage_editor,
    );

# feed several editor calls to $editor

$editor->replay ($other_editor);

=cut

require SVK::MergeEditor;

sub replay {
    my ($self, $editor, $base_rev) = @_;
	my $edit = SVN::Simple::Edit->new
	    (_editor => [$editor],
	     pool => SVN::Pool->new ($self->{pool}),
	     missing_handler => sub { my ($self, $path) = @_;
				      $self->{added}{$path} ?
					  $self->add_directory ($path) : $self->open_directory($path);
				  });

    $edit->open_root ($base_rev);

    for (sort keys %{$self->{files}}) {
	my $fname = ${*{$self->{files}{$_}}};
	my $fh;
	$edit->add_file ($_)
	    if $self->{added}{$_};
	open $fh, $fname;
	$edit->modify_file ($_, $fh, $self->{md5}{$_});
    }
    $edit->close_edit;
}

sub cb_exist {
    my ($self, $path) = @_;
    return 1 if exists $self->{files}{$path};
    $path = $self->{tgt_anchor}.'/'.$path;;
    $self->{base_root}->check_path ($path) != $SVN::Node::none;
}

sub cb_localmod {
    my ($self, $path, $checksum, $pool) = @_;
    if (exists $self->{files}{$path}) {
	return if $self->{md5}{$path} eq $checksum;
	my $fname = ${*{$self->{files}{$path}}};
	open my ($fh), $fname or die $!;
	return [$fh, $fname, $self->{md5}{$path}];
    }

    $path = $self->{tgt_anchor}.'/'.$path;;
    my $md5 = $self->{base_root}->file_md5_checksum ($path);
    return if $md5 eq $checksum;
    return [$self->{base_root}->file_contents ($path), undef, $md5];
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    $self->{added}{$path} = 1;
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, @arg) = @_;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum) = @_;
#    my $pool = $self->{pool};
#    $pool->default if $pool && $pool->can ('default');
    my $base;

    if (exists $self->{files}{$path}) {
	$base = $self->{files}{$path};
	my $fname = ${*$base};
	open $base, $fname;
	${*$base} = $fname;
    }
    else {
	$base = $self->{base_root}->file_contents ("$self->{tgt_anchor}/$path")
	    unless $self->{added}{$path};
    }

    my ($fh, $file) = mkstemps ('svk-combineXXXXX', '.tmp');
    $self->{files}{$path} = $fh;

    ${*$fh} = $file;
    $self->{base}{$path} = $base;

    $base ||= SVN::Core::stream_empty();
    return [SVN::TxDelta::apply ($base, $fh, undef, undef)];
}

sub close_file {
    my ($self, $path, $md5) = @_;
    unlink ${*{$self->{base}{$path}}}
	if $self->{base}{$path} && ${*{$self->{base}{$path}}};
    $self->{md5}{$path} = $md5;
}

sub DESTROY {
    my ($self) = @_;
    for (keys %{$self->{files}}) {
	unlink ${*{$self->{files}{$_}}};
    }
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
