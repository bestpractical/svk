package SVN::MergeEditor;
use strict;
our $VERSION = '0.03';
our @ISA = qw(SVN::Delta::Editor);

=head1 NAME

SVN::MergeEditor - An editor wrapper that merges for the storage editor

=head1 SYNOPSIS

$editor = SVN::MergeEditor->new
    ( anchor => $anchor,
      base_anchor => $base_anchor,
      base_root => $fs->revision_root ($arg{fromrev}),
      target => $target,
      storage => $storage_editor,
      %cb,
    );


=head1 DESCRIPTION

Given the base root and callbacks for local tree, SVN::MergeEditor
forwards the incoming editor calls to the storage editor for modifying
the local tree, and merges the tree delta and text delta
transparently.

=head1 PARAMETERS

=head2 options for base and target tree

=head3 anchor

The anchor of the target tree.

=head3 target

The target path component of the target tree.

=head3 base_annchor

The anchor of the base tree.

=head3 base_root

The root object of the base tree.

=head3 storage

=head2 callbacks for local tree

Since the merger needs to have information about the local tree, some
callbacks must be supplied.

=head3 cb_exist

Check if the given path exists.

=head3 cb_rev

Check the revision of the given path.

=head3 cb_conflict

Called when a conflict is detected.

=head3 cb_localmod

Called when the merger needs to retrieve the local modification of a
file. Return an arrayref of filename, filehandle, and md5. Return
undef if there is no local modification.

=head3 cb_merged

Called right before closing the top directory with storage editor,
root baton, and pool.

=cut

use Digest::MD5;
use Algorithm::Merge;
use YAML;
use File::Temp qw/:mktemp/;

sub md5 {
    my $fh = shift;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
    $self->{storage}->set_target_revision ($revision);
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{baserev} = $baserev;
    $self->{storage_baton}{''} =
	$self->{storage}->open_root (&{$self->{cb_rev}}(''));
    return '';
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    # tag for merge of file adding
    $self->{info}{$path}{status} = (&{$self->{cb_exist}}($path) ? undef : ['A']);
    $self->{storage_baton}{$path} =
	$self->{storage}->add_file ($path, $self->{storage_baton}{$pdir}, @arg)
	if $self->{info}{$path}{status};
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    # modified but rm locally - tag for conflict?
    $self->{info}{$path}{status} = (&{$self->{cb_exist}}($path) ? [] : undef);
    $self->{info}{$path}{open} = [$pdir, $rev, $pool]
	if $self->{info}{$path}{status};
    return $path;
}

sub ensure_open {
    my ($self, $path) = @_;
    return unless $self->{info}{$path}{open};
    my ($pdir, $rev, $pool) = @{$self->{info}{$path}{open}};
    $self->{storage_baton}{$path} ||=
	$self->{storage}->open_file ($path, $self->{storage_baton}{$pdir},
				     &{$self->{cb_rev}}($path), $pool);

}

sub cleanup_fh {
    my ($self, $fh) = @_;
    for (qw/base new local/) {
	close $fh->{$_}[0]
	    if $fh->{$_}[0];
	unlink $fh->{$_}[1]
	    if $fh->{$_}[1]
    }
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $self->{info}{$path}{status};
    my ($base, $newname);
    unless ($self->{info}{$path}{status}[0]) { # open, has base
	$self->{info}{$path}{fh}{local} =
	    &{$self->{cb_localmod}}($path, $checksum) or
		$self->{info}{$path}{status}[0] = 'U';
	    # retrieve base
	    $self->{info}{$path}{fh}{base} = [mkstemps("/tmp/svk-mergeXXXXX", '.tmp')];
	    my $rpath = $path;
	    $rpath = "$self->{base_anchor}/$rpath" if $self->{base_anchor};
	    my $buf = $self->{base_root}->file_contents ($rpath);
	    local $/;
	    $self->{info}{$path}{fh}{base}[0]->print(<$buf>);
	    seek $self->{info}{$path}{fh}{base}[0], 0, 0;
	    # get new
	    my ($fh, $file) = mkstemps("/tmp/svk-mergeXXXXX", '.tmp');
	    $self->{info}{$path}{fh}{new} = [$fh, $file];
	    return [SVN::TxDelta::apply ($self->{info}{$path}{fh}{base}[0],
					 $fh, undef, undef, $pool)];
    }
    $self->{info}{$path}{status}[0] ||= 'U';
    $self->ensure_open ($path);
    return $self->{storage}->apply_textdelta ($self->{storage_baton}{$path},
					      $checksum, $pool);
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    my $info = $self->{info}{$path};
    my $fh = $info->{fh};
    no warnings 'uninitialized';

    # let close_directory reports about its children
    if ($info->{fh}{new}) {
	my ($orig, $new, $local) =
	    map {$fh->{$_} && $fh->{$_}[0]} qw/base new local/;
	seek $orig, 0, 0;
	open $new, $fh->{new}[1];
	{
	    local $/;
	    $orig = <$orig>;
	    $new = <$new>;
	    $local = <$local> if $local;
	}

	if ($new eq $orig || $new eq $local) {
	    $self->cleanup_fh ($fh);
	    delete $self->{info}{$path};
	    $checksum = Digest::MD5::md5_hex ($new)
		if $new eq $orig;
	    undef $checksum if $local;
	    $self->{info}{$path}{status}[0] = 'g'
		if $new eq $local;
	    return;
	}

	$self->ensure_open ($path);
	unless ($local) {
	    my $handle = $self->{storage}->
		apply_textdelta ($self->{storage_baton}{$path}, $fh->{base}[2],
				 $pool);

	    SVN::TxDelta::send_string ($new, @$handle, $pool)
		    if $handle && $#{$handle} > 0;
	    $self->{storage}->close_file ($self->{storage_baton}{$path},
					  $checksum, $pool);
	    $self->cleanup_fh ($fh);
	    return;
	}

	my @mergearg =
	    ([split "\n", $orig],
	     [split "\n", $new],
	     [split "\n", $local],
	    );
	# merge consistencies check
	my $diff3 = Algorithm::Merge::diff3 (@mergearg);

	for (@$diff3) {
	    if ($_->[0] eq 'u' && ($_->[1] ne $_->[2] || $_->[2] ne $_->[3])) {
		my $file = '/tmp/svk-merge-bug.yml';
		unlink ($file);
		YAML::DumpFile ($file, { orig => $orig, new => $new,
					 local => $local ,diff3 => $diff3 });
		$self->cleanup_fh ($fh);
		die "merge result inconsistent while merging $path, please send the file $file to {clkao,jsmith}\@cpan.org";
	    }
	}

	# XXX: use traverse so we just output the result instead of
	# buffering it
	$info->{status}[0] = 'G';
	my $merged = eval {Algorithm::Merge::merge (@mergearg,
	     {CONFLICT => sub {
		  my ($left, $right) = @_;
		  $info->{status}[0] = 'C';
		  q{<!-- ------ START CONFLICT ------ -->},
		  (@$left),
		  q{<!-- ---------------------------- -->},
		  (@$right),
		  q{<!-- ------  END  CONFLICT ------ -->},
	      }}) };
	die $@ if $@;

	$self->cleanup_fh ($fh);
	my $handle = $self->{storage}->
	    apply_textdelta ($self->{storage_baton}{$path}, $fh->{local}[2],
			     $pool);

	$merged = (join("\n", @$merged)."\n");
	SVN::TxDelta::send_string ($merged, @$handle, $pool)
		if $handle && $#{$handle} > 0;
	$checksum = Digest::MD5::md5_hex ($merged);
	&{$self->{cb_conflict}} ($path)
	    if $info->{status}[0] eq 'C';
    }

    if ($info->{status}) {
	print sprintf ("%1s%1s \%s\n", $info->{status}[0],
		       $info->{status}[1], $path)
	    if $info->{status}[0] || $info->{status}[1];
	$self->{storage}->close_file ($self->{storage_baton}{$path},
				      $checksum, $pool)
	    if $self->{storage_baton}{$path};
    }
    else {
	print "   $path - skipped\n";
    }
    delete $self->{info}{$path};
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    $self->{storage_baton}{$path} =
	$self->{storage}->add_directory ($path, $self->{storage_baton}{$pdir},
					 @arg);
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, @arg) = @_;
    $self->{storage_baton}{$path} =
	$self->{storage}->open_directory ($path, $self->{storage_baton}{$pdir},
					  &{$self->{cb_rev}}($path), @arg);
    return $path;
}

sub close_directory {
    my ($self, $path, $pool) = @_;
    no warnings 'uninitialized';

    for (grep {$path ? "$path/" eq substr ($_, 0, length($path)+1) : 1}
	 keys %{$self->{info}}) {
	print sprintf ("%1s%1s \%s\n", $self->{info}{$_}{status}[0],
		       $self->{info}{$_}{status}[1], $_);
	delete $self->{info}{$_};
    }

    &{$self->{cb_merged}} ($self->{storage}, $self->{storage_baton}{''}, $pool)
	if $path eq '' && $self->{cb_merged};

    $self->{storage}->close_directory ($self->{storage_baton}{$path}, $pool);
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
    return unless &{$self->{cb_exist}}($path);

    $self->{storage}->delete_entry ($path, $revision,
				    $self->{storage_baton}{$pdir}, @arg);
    $self->{info}{$path}{status} = ['D'];
}

sub change_file_prop {
    my ($self, $path, @arg) = @_;
    return unless $self->{info}{$path}{status};
    $self->ensure_open ($path);
    $self->{storage}->change_file_prop ($self->{storage_baton}{$path}, @arg);
    $self->{info}{$path}{status}[1] = 'U';
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
    # XXX: need the status-fu like files to track removed / renamed
    # directories
    # return unless $self->{info}{$path}{status};

    # there should be a magic flag indicating if svk:merge prop should
    # be dealt.
    return if $arg[0] eq 'svk:merge';
    $self->{storage}->change_dir_prop ($self->{storage_baton}{$path}, @arg);
    $self->{info}{$path}{status}[1] = 'U';
}

sub close_edit {
    my ($self, @arg) = @_;
    $self->{storage}->close_edit(@arg);
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
