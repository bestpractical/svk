package SVN::DiffEditor;
use strict;
our $VERSION = '0.04';
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
    return unless defined $self->{info}{$path}{new};

    my $base = $self->{info}{$path}{added} ?
	\'' : $self->{cb_basecontent} ($path);
    my $llabel = $self->{llabel} || &{$self->{cb_llabel}} ($path);
    my $rlabel = $self->{rlabel} || &{$self->{cb_rlabel}} ($path);

    output_diff ($path, $llabel, $rlabel, $base, \$self->{info}{$path}{new});

    delete $self->{info}{$path};
}

sub output_diff {
    my ($path, $llabel, $rlabel, $ltext, $rtext) = @_;

    # XXX: this slurp is dangerous. waiting for streamy svndiff routine
    local $/;
    $ltext = \<$ltext> if ref ($ltext) && ref ($ltext) ne 'SCALAR';
    $rtext = \<$rtext> if ref ($rtext) && ref ($rtext) ne 'SCALAR';

    print "Index: $path\n";
    print '=' x 66,"\n";
    print "--- $path  ($llabel)\n";
    print "+++ $path  ($rlabel)\n";
    print Text::Diff::diff ($ltext, $rtext);
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
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
}

sub change_file_prop {
    my ($self, $path, @arg) = @_;
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
}

sub close_edit {
    my ($self, @arg) = @_;
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
