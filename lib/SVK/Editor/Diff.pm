package SVK::Editor::Diff;
use strict;
use SVN::Delta;
our $VERSION = '0.09';
our @ISA = qw(SVN::Delta::Editor);

use SVK::I18N;
use SVK::Util qw( slurp_fh tmpfile );
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

    my $new;
    if ($self->{external}) {
	my $tmp = tmpfile ('diff');
	slurp_fh ($self->{info}{$path}{base}, $tmp)
	    if $self->{info}{$path}{base};
	seek $tmp, 0, 0;
	$self->{info}{$path}{base} = $tmp;
	$self->{info}{$path}{new} = $new = tmpfile ('diff');
    }
    else {
	open $new, '>', \$self->{info}{$path}{new};
    }

    return [SVN::TxDelta::apply ($self->{info}{$path}{base}, $new,
				 undef, undef, $pool)];
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    if ($self->{info}{$path}{new}) {
	my $base = $self->{info}{$path}{added} ?
	    \'' : $self->{cb_basecontent} ($path);
	my $llabel = $self->{llabel} || $self->{cb_llabel}->($path);
	my $rlabel = $self->{rlabel} || $self->{cb_rlabel}->($path);

	if ($self->{external}) {
	    # XXX: the 2nd file could be - and save some disk IO
	    system (split (' ', $self->{external}),
		    '-L', _full_label ($path, undef, $llabel),
		    $self->{info}{$path}{base}->filename,
		    '-L', _full_label ($path, undef, $rlabel),
		    $self->{info}{$path}{new}->filename);
	}
	else {
	    output_diff ($path, $llabel, $rlabel,
			 $self->{lpath} || '', $self->{rpath} || '',
			 $base, \$self->{info}{$path}{new});
	}
    }

    $self->output_prop_diff ($path, $pool);
    delete $self->{info}{$path};
}

sub _full_label {
    my ($path, $mypath, $label) = @_;
    return "$path ".($mypath ? "  ($mypath)  " : '')." ($label)";
}

sub output_diff {
    my ($path, $llabel, $rlabel, $lpath, $rpath, $ltext, $rtext) = @_;

    # XXX: this slurp is dangerous. waiting for streamy svndiff routine
    local $/;
    $ltext = \<$ltext> if ref ($ltext) && ref ($ltext) ne 'SCALAR';
    $rtext = \<$rtext> if ref ($rtext) && ref ($rtext) ne 'SCALAR';

    my $showpath = ($lpath ne $rpath);
    print "=== $path\n";
    print '=' x 66,"\n";
    print "--- "._full_label ($path, $showpath ? $lpath : undef, $llabel)."\n";
    print "+++ "._full_label ($path, $showpath ? $rpath : undef, $rlabel)."\n";
    print Text::Diff::diff ($ltext, $rtext);
}

sub output_prop_diff {
    my ($self, $path, $pool) = @_;
    if ($self->{info}{$path}{prop}) {
	print "\n", loc("Property changes on: %1\n", $path), ('_' x 67), "\n";
	for (sort keys %{$self->{info}{$path}{prop}}) {
	    print loc("Name: %1\n", $_);
	    my $baseprop;
	    $baseprop = $self->{cb_baseprop}->($path, $_)
		unless $self->{info}{$path}{added};
	    print Text::Diff::diff (\ ($baseprop || ''),
				    \$self->{info}{$path}{prop}{$_},
				    { STYLE => 'SVK::Editor::Diff::NoHeader' });
	}
	print "\n\n";
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

package SVK::Editor::Diff::NoHeader;

our @ISA = qw(Text::Diff::Unified);

sub hunk_header {
    return '';
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
