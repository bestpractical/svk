package SVK::Editor::Diff;
use strict;
use SVN::Delta;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVN::Delta::Editor);

use SVK::I18N;
use SVK::Util qw( slurp_fh tmpfile mimetype_is_text catfile );
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
    my $info = $self->{info}{$path} ||= {};
    $info->{new} = '';
    $info->{base} = $self->{cb_basecontent} ($path)
	unless $info->{added};

    unless ($self->{external}) {
	my $newtype = $info->{prop} && $info->{prop}{'svn:mime-type'};
	my $is_text = !$newtype || mimetype_is_text ($newtype);
	if ($is_text) {
	    my $basetype = $self->{cb_baseprop}->($path, 'svn:mime-type');
	    $is_text = !$basetype || mimetype_is_text ($basetype);
	}
	unless ($is_text) {
	    print "=== $path\n";
	    print '=' x 66,"\n";
	    print loc("Cannot display: file marked as a binary type.\n");
	    return undef;
	}
    }

    my $new;
    if ($self->{external}) {
	my $tmp = tmpfile ('diff');
	slurp_fh ($info->{base}, $tmp)
	    if $info->{base};
	seek $tmp, 0, 0;
	$info->{base} = $tmp;
	$info->{new} = $new = tmpfile ('diff');
    }
    else {
	open $new, '>', \$info->{new};
    }

    return [SVN::TxDelta::apply ($info->{base}, $new,
				 undef, undef, $pool)];
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    if ($self->{info}{$path}{new}) {
	no warnings 'uninitialized';
	my $rpath = $self->{report} ? catfile($self->{report}, $path) : $path;
	my $base = $self->{info}{$path}{added} ?
	    \'' : $self->{cb_basecontent} ($path);
	my @label = map { $self->{$_} || $self->{"cb_$_"}->($path) } qw/llabel rlabel/;
	my $showpath = ($self->{lpath} ne $self->{rpath});
	my @showpath = map { $showpath ? $self->{$_} : undef } qw/lpath rpath/;
	if ($self->{external}) {
	    # XXX: the 2nd file could be - and save some disk IO
	    my @content = map { ($self->{info}{$path}{$_}->filename) } qw/base new/;
	    @content = reverse @content if $self->{reverse};
	    system (split (' ', $self->{external}),
		    '-L', _full_label ($rpath, $showpath[0], $label[0]),
		    $content[0],
		    '-L', _full_label ($rpath, $showpath[1], $label[1]),
		    $content[1]);
	}
	else {
	    my @content = ($base, \$self->{info}{$path}{new});
	    @content = reverse @content if $self->{reverse};
	    output_diff ($rpath, @label, @showpath, @content);
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

    print "=== $path\n";
    print '=' x 66,"\n";
    print "--- "._full_label ($path, $lpath, $llabel)."\n";
    print "+++ "._full_label ($path, $rpath, $rlabel)."\n";
    print Text::Diff::diff ($ltext, $rtext);
}

sub output_prop_diff {
    my ($self, $path, $pool) = @_;
    if ($self->{info}{$path}{prop}) {
	my $rpath = $self->{report} ? catfile($self->{report}, $path) : $path;
	print "\n", loc("Property changes on: %1\n", $rpath), ('_' x 67), "\n";
	for (sort keys %{$self->{info}{$path}{prop}}) {
	    print loc("Name: %1\n", $_);
	    my $baseprop;
	    $baseprop = $self->{cb_baseprop}->($path, $_)
		unless $self->{info}{$path}{added};
            my @args =
                map \$_,
                map { (length || /\n$/) ? "$_\n" : $_ }
                    ($baseprop||''), ($self->{info}{$path}{prop}{$_}||'');
            @args = reverse @args if $self->{reverse};
	    print Text::Diff::diff (@args,
				    { STYLE => 'SVK::Editor::Diff::PropDiff' });
	}
	print "\n";
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
    # generate delta between empty root and oldroot of $path, then reverse in output
    $self->{xd}->depot_delta
	( oldroot => $self->{oldtarget}{repos}->fs->revision_root (0),
	  oldpath => [$self->{oldtarget}{path}, $path],
	  newroot => $self->{oldroot},
	  newpath => $self->{oldtarget}{path} eq '/' ? "/$path" : "$self->{oldtarget}{path}/$path",
	  editor => __PACKAGE__->new (%$self, reverse => 1),
	);

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

package SVK::Editor::Diff::PropDiff;

our @ISA = qw(Text::Diff::Unified);

sub hunk_header {
    return '';
}

sub hunk {
    my $self = shift;

    my $s = $self->SUPER::hunk (@_);
    $s =~ s/^/ /gm;
    $s;
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
