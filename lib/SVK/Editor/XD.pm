package SVK::Editor::XD;
use SVK::I18N;
require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);
use File::Path;
use SVK::Util qw( get_anchor md5 );

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
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 already exists", $path) if -e $copath;
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    die loc("path %1 does not exist", $path) unless -e $copath;
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    my $base;
    return if $self->{check_only};
    my $copath = $path;
    $self->{get_copath}($copath);
    if (-e $copath) {
	my ($dir,$file) = get_anchor (1, $copath);
	my $basename = "$dir.svk.$file.base";
	$base = SVK::XD::get_fh ($self->{oldroot}, '<',
				 "$self->{anchor}/$path", $copath);
	if ($checksum) {
	    my $md5 = md5($base);
	    die loc("source checksum mismatch") if $md5 ne $checksum;
	    seek $base, 0, 0;
	}
	rename ($copath, $basename);
	$self->{base}{$path} = [$base, $basename];
    }
    my $fh = SVK::XD::get_fh ($self->{newroot}, '>',
			      "$self->{anchor}/$path", $copath)
	or warn "can't open $path";

    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty($pool),
				 $fh, undef, undef, $pool)];
}

sub close_file {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    if ($self->{base}{$path}) {
	close $self->{base}{$path}[0];
	unlink $self->{base}{$path}[1];
	delete $self->{base}{$path};
    }
    elsif (!$self->{update} && !$self->{check_only}) {
	my $report = $path;
	$report =~ s/^\Q$self->{target}\E/$self->{report}/;
	$self->{xd}->do_add (report => $report,
			     copath => $copath, quiet => $self->{quiet});
    }
    $self->{checkout}->store ($copath, {revision => $self->{revision}})
	if $self->{update};
    chmod 0755, $copath
	if $self->{exe}{$path};
}

sub add_directory {
    my ($self, $path) = @_;
    my $copath = $path;
    $self->{get_copath}($copath);
    mkdir ($copath) unless $self->{check_only};
    my $report = $path;
    $report =~ s/^\Q$self->{target}\E/$self->{report}/;
    $self->{xd}->do_add (report => $report,
			 copath => $copath, quiet => $self->{quiet})
	if !$self->{update} && !$self->{check_only};
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
    # XXX: check if everyone under $path is sane for delete";
    return if $self->{check_only};
    if ($self->{update}) {
	-d $copath ? rmtree ([$copath]) : unlink($copath);
    }
    else {
	$self->{xd}->do_delete (%$self,
				path => "$self->{anchor}/$path",
				copath => $copath,
				quiet => 1);
    }
}

sub close_directory {
    my ($self, $path) = @_;
    my $copath = $path;
    eval {$self->{get_copath}($copath)};
    undef $@, return if $@;
    $self->{checkout}->store_recursively ($copath,
					  {revision => $self->{revision},
					   '.deleted' => undef})
	if $self->{update};
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    return if $self->{check_only};
    my $copath = $path;
    $self->{get_copath}($copath);
    # XXX: do executable unset also.
    $self->{exe}{$path}++
	if $name eq 'svn:executable' && defined $value;
    $self->{xd}->do_propset ( quiet => 1,
			      copath => $copath,
			      propname => $name,
			      propvalue => $value,
			    )
	unless $self->{update};
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
