package SVK::MergeEditor;
use strict;
our $VERSION = '0.14';
our @ISA = qw(SVN::Delta::Editor);
use SVK::Notify;
use SVK::Util qw( slurp_fh md5 get_anchor );

=head1 NAME

SVK::MergeEditor - An editor wrapper that merges for the storage editor

=head1 SYNOPSIS

$editor = SVK::MergeEditor->new
    ( anchor => $anchor,
      base_anchor => $base_anchor,
      base_root => $fs->revision_root ($arg{fromrev}),
      target => $target,
      storage => $storage_editor,
      %cb,
    );


=head1 DESCRIPTION

Given the base root and callbacks for local tree, SVK::MergeEditor
forwards the incoming editor calls to the storage editor for modifying
the local tree, and merges the tree delta and text delta
transparently.

=head1 PARAMETERS

=head2 options for base and target tree

=over

=item anchor

The anchor of the target tree.

=item target

The target path component of the target tree.

=item base_anchor

The anchor of the base tree.

=item base_root

The root object of the base tree.

=item storage

The editor that will receive the merged callbacks.

=back

=head2 callbacks for local tree

Since the merger needs to have information about the local tree, some
callbacks must be supplied.

=over

=item cb_exist

Check if the given path exists.

=item cb_rev

Check the revision of the given path.

=item cb_conflict

Called when a conflict is detected.

=item cb_localmod

Called when the merger needs to retrieve the local modification of a
file. Return an arrayref of filename, filehandle, and md5. Return
undef if there is no local modification.

=item cb_merged

Called right before closing the top directory with storage editor,
root baton, and pool.

=item cb_closed

Called after each file close call.

=back

=cut

use Digest::MD5 qw(md5_hex);
use File::Compare ();
use File::Temp qw/:mktemp/;

sub set_target_revision {
    my ($self, $revision) = @_;
    $self->{revision} = $revision;
    $self->{storage}->set_target_revision ($revision);
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{baserev} = $baserev;
    $self->{notify} = SVK::Notify->new ();
    $self->{storage_baton}{''} =
	$self->{storage}->open_root (&{$self->{cb_rev}}($self->{target}||''));
    return '';
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    # tag for merge of file adding
    unless (!defined $pdir || &{$self->{cb_exist}}($path)) {
	$self->{notify}->node_status ($path) = 'A';
	$self->{storage_baton}{$path} =
	    $self->{storage}->add_file ($path, $self->{storage_baton}{$pdir}, @arg);
	return $path;
    }
    $self->{notify}->flush ($path);
    return undef;
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    # modified but rm locally - tag for conflict?
    if (defined $pdir && &{$self->{cb_exist}}($path)) {
	$self->{info}{$path}{open} = [$pdir, $rev];
	$self->{info}{$path}{fpool} = $pool;
	return $path;
    }
    $self->{notify}->flush ($path);
    return undef;
}

sub ensure_open {
    my ($self, $path) = @_;
    return unless $self->{info}{$path}{open};
    my ($pdir, $rev, $pool) = (@{$self->{info}{$path}{open}},
			       $self->{info}{$path}{fpool});
    $self->{storage_baton}{$path} ||=
	$self->{storage}->open_file ($path, $self->{storage_baton}{$pdir},
				     &{$self->{cb_rev}}($path), $pool);
    delete $self->{info}{$path}{open};
}

sub ensure_close {
    my ($self, $path, $checksum, $pool) = @_;

    $self->cleanup_fh ($self->{info}{$path}{fh});
    $self->{notify}->flush ($path, 1);
    &{$self->{cb_closed}} ($path, $checksum, $pool)
        if $self->{cb_closed};
    $self->{storage}->close_file ($self->{storage_baton}{$path},
				  $checksum, $pool)
        if $self->{storage_baton}{$path};

    delete $self->{info}{$path};
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

sub prepare_fh {
    my ($self, $fh) = @_;
    for my $name (qw/base new local/) {
	next unless $fh->{$name}[0];
	next if $fh->{$name}[1];
	my $tmp = [mkstemps("/tmp/svk-mergeXXXXX", '.tmp')];
	my $slurp = $fh->{$name}[0];

	slurp_fh ($slurp, $tmp->[0]);

	close $fh->{$name}[0];
	$fh->{$name} = $tmp;
	seek $fh->{$name}[0], 0, 0;
    }
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $path;
    my $info = $self->{info}{$path};
    my $fh = $info->{fh} = {};
    $pool->default if $pool && $pool->can ('default');
    my ($base, $newname);
    if ($info->{fpool}) { # open, has base
	$pool = $self->{info}{$path}{fpool};
	$fh->{local} = &{$self->{cb_localmod}}($path, $checksum, $pool) or
	    $self->{notify}->node_status ($path) = 'U';
	# retrieve base
	$fh->{base} = [mkstemps("/tmp/svk-mergeXXXXX", '.tmp')];
	my $rpath = $path;
	$rpath = "$self->{base_anchor}/$rpath" if $self->{base_anchor};
	my $buf = $self->{base_root}->file_contents ($rpath, $pool);
	slurp_fh ($buf, $fh->{base}[0]);
	seek $fh->{base}[0], 0, 0;
	# get new
	$fh->{new} = [mkstemps("/tmp/svk-mergeXXXXX", '.tmp')];
	return [SVN::TxDelta::apply ($fh->{base}[0],
				     $fh->{new}[0], undef, undef, $pool)];
    }
    $self->{notify}->node_status ($path) ||= 'U';
    $self->ensure_open ($path);
    return $self->{storage}->apply_textdelta ($self->{storage_baton}{$path},
					      $checksum, $pool);
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    return unless $path;
    $pool->default if $pool && $pool->can ('default');
    my $info = $self->{info}{$path};
    my $fh = $info->{fh};

    no warnings 'uninitialized';
    # let close_directory reports about its children
    if ($info->{fh}{new}) {
	$self->prepare_fh ($fh);

	if (File::Compare::compare ($fh->{new}[1], $fh->{base}[1]) == 0 ||
	    ($fh->{local}[0] && File::Compare::compare ($fh->{new}[1], $fh->{local}[1]) == 0)) {
	    $self->{notify}->node_status ($path) = 'g';
	    $self->ensure_close ($path, $checksum, $pool);
	    return;
	}

	$self->ensure_open ($path);
	unless ($fh->{local}[0]) {
	    my $handle = $self->{storage}->
		apply_textdelta ($self->{storage_baton}{$path}, $fh->{base}[2],
				 $pool);

	    if ($handle && $#{$handle} >= 0) {
		open my ($new), $fh->{new}[1];
		if ($self->{send_fulltext}) {
		    SVN::TxDelta::send_stream ($new, @$handle, $pool);
		}
		else {
		    my $txstream = SVN::TxDelta::new
			($fh->{base}[0], $new, $pool);

		    SVN::TxDelta::send_txstream ($txstream, @$handle, $pool)
		}
	    }

	    $self->ensure_close ($path, $checksum, $pool);
	    return;
	}

	my $diff = SVN::Core::diff_file_diff3
	    (map {$fh->{$_}[1]} qw/base local new/);
	open my $mfh, '+>', \(my $merged);
	SVN::Core::diff_file_output_merge
		( $mfh, $diff,
		  (map {
		      $fh->{$_}[1]
		  } qw/base local new/),
		  "||||||| base",
		  "<<<<<<< local",
		  ">>>>>>> new",
		  "=======",
		  1, 0, $pool);

        $self->{notify}->node_status ($path) =
	    SVN::Core::diff_contains_conflicts ($diff) ? 'C' : 'G';

	my $handle = $self->{storage}->
	    apply_textdelta ($self->{storage_baton}{$path}, $fh->{local}[2],
			     $pool);

	$checksum = md5_hex ($merged);

	if ($handle && $#{$handle} >= 0) {
	    seek $mfh, 0, 0;
	    seek $fh->{local}[0], 0, 0;
	    if ($self->{send_fulltext}) {
		SVN::TxDelta::send_stream ($mfh, @$handle, $pool)
			if $handle && $#{$handle} >= 0;
	    }
	    else {
		my $txstream = SVN::TxDelta::new
		    ($fh->{local}[0], $mfh, $pool);
		SVN::TxDelta::send_txstream ($txstream, @$handle, $pool)
	    }
	}

	close $mfh;
	$self->cleanup_fh ($fh);

	&{$self->{cb_conflict}} ($path)
	    if $self->{notify}->node_status ($path) eq 'C';
    }
    elsif ($info->{fpool} && $self->{notify}->node_status ($path) ne 'A') {
	# open but prop edit only, load local checksum
	if (my $local = &{$self->{cb_localmod}} ($path, $checksum, $pool)) {
	    $checksum = $local->[2];
	    close $local->[0];
	}
    }

    $self->ensure_close ($path, $checksum, $pool);
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    return undef unless defined $pdir;
    if (&{$self->{cb_exist}}($path)) {
	$self->{notify}->flush ($path) ;
	return undef;
    }
    $self->{storage_baton}{$path} =
	$self->{storage}->add_directory ($path, $self->{storage_baton}{$pdir},
					 @arg);
    $self->{notify}->node_status ($path) = 'A';
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, @arg) = @_;
    return undef unless defined $pdir;
    unless (&{$self->{cb_exist}}($path)) {
	$self->{notify}->flush ($path) ;
	return undef;
    }

    $self->{storage_baton}{$path} =
	$self->{storage}->open_directory ($path, $self->{storage_baton}{$pdir},
					  &{$self->{cb_rev}}($path), @arg);
    return $path;
}

sub close_directory {
    my ($self, $path, $pool) = @_;
    return unless defined $path;
    no warnings 'uninitialized';

    $self->{notify}->flush_dir ($path);

    &{$self->{cb_merged}} ($self->{storage}, $self->{storage_baton}{''}, $pool)
	if $path eq '' && $self->{cb_merged};

    $self->{storage}->close_directory ($self->{storage_baton}{$path}, $pool);
}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
    no warnings 'uninitialized';
    return unless defined $pdir && &{$self->{cb_exist}}($path);

    $self->{storage}->delete_entry ($path, &{$self->{cb_rev}}($path),
				    $self->{storage_baton}{$pdir}, @arg);
    $self->{notify}->node_status ($path) = 'D';
}

sub change_file_prop {
    my ($self, $path, @arg) = @_;
    return unless $path;
    $self->ensure_open ($path);
    $self->{storage}->change_file_prop ($self->{storage_baton}{$path}, @arg);
    $self->{notify}->prop_status ($path) = 'U';
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
    $self->{notify}->prop_status ($path) = 'U';
}

sub close_edit {
    my ($self, @arg) = @_;
    if (defined $self->{storage_baton}{''}) {
	$self->{storage}->close_edit(@arg);
    }
    else {
	$self->{storage}->abort_edit(@arg);
    }
}

=head1 BUGS

=over

=item Tree merge

still very primitive, have to handle lots of cases

=back

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
