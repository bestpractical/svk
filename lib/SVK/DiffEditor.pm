package SVK::DiffEditor;
use strict;
use SVN::Delta;
our $VERSION = '0.09';
our @ISA = qw(SVN::Delta::Editor);

use IO::String;
use Text::Diff;

sub set_target_revision {
    my ($self, $revision) = @_;
}

sub open_root {
    my ($self, $baserev) = @_;
    return '';
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    $self->{info}{$path}{added} = 1;
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    $self->{info}{$path}{new} = '';
    $self->{info}{$path}{base} = $self->{cb_basecontent} ($path)
	unless $self->{info}{$path}{added};

    return [SVN::TxDelta::apply ($self->{info}{$path}{base},
				 IO::String->new (\$self->{info}{$path}{new}),
				 undef, undef, $pool)];
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    if ($self->{info}{$path}{new}) {
	my $base = $self->{info}{$path}{added} ?
	    \'' : $self->{cb_basecontent} ($path);
	my $llabel = $self->{llabel} || &{$self->{cb_llabel}} ($path);
	my $rlabel = $self->{rlabel} || &{$self->{cb_rlabel}} ($path);

	output_diff ($self->{fh} || \*STDOUT, $path, $llabel, $rlabel,
		     $self->{lpath} || '', $self->{rpath} || '',
		     $base, \$self->{info}{$path}{new});
    }

    $self->output_prop_diff ($path, $pool);
    delete $self->{info}{$path};
}

sub output_diff {
    my ($fh, $path, $llabel, $rlabel, $lpath, $rpath, $ltext, $rtext) = @_;

    # XXX: this slurp is dangerous. waiting for streamy svndiff routine
    local $/;
    $ltext = \<$ltext> if ref ($ltext) && ref ($ltext) ne 'SCALAR';
    $rtext = \<$rtext> if ref ($rtext) && ref ($rtext) ne 'SCALAR';

    my $showpath = ($lpath ne $rpath);
    print $fh "Index: $path\n";
    print $fh '=' x 66,"\n";
    print $fh "--- $path ".($showpath ? "  ($lpath)  " : '')." ($llabel)\n";
    print $fh "+++ $path ".($showpath ? "  ($rpath)  " : '')." ($rlabel)\n";
    print $fh Text::Diff::diff ($ltext, $rtext);
}

sub output_prop_diff {
    my ($self, $path, $pool) = @_;
    if ($self->{info}{$path}{prop}) {
	my $fh = $self->{fh} || \*STDOUT;
	print $fh "\nProperty changes on: $path\n".('_' x 67)."\n";
	for (keys %{$self->{info}{$path}{prop}}) {
	    print $fh "Name: $_\n";
	    print $fh  Text::Diff::diff (\(&{$self->{cb_baseprop}} ($path, $_) || ''),
		\$self->{info}{$path}{prop}{$_});
	}
    }
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, @arg) = @_;
    return $path;
}

sub close_directory {
    my ($self, $path, $pool) = @_;
    $self->output_prop_diff ($path, $pool);
    delete $self->{info}{$path};
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    $self->{info}{$path}{prop}{$name} = $value;
}

sub change_dir_prop {
    my ($self, $path, $name, $value) = @_;
    $self->{info}{$path}{prop}{$name} = $value;
}

sub close_edit {
    my ($self, @arg) = @_;
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
