package SVK::Editor::Rename;
use strict;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVK::Editor::Patch);
use SVK::Editor::Patch;
use SVK::Notify;
use SVK::I18N;
#use SVK::Util qw( slurp_fh md5 get_anchor tmpfile );

=head1 NAME

SVK::Editor::Rename - An editor that translates editor calls for renamed entries

=head1 SYNOPSIS

  $editor = SVK::Editor::Rename->new
    ( editor => $next_editor,
      base_root => $fs->revision_root ($arg{fromrev}),
      target => $target,
      storage => $storage_editor,
      %cb,
    );

=head1 DESCRIPTION

Given the base root and callbacks for local tree, SVK::Editor::Merge
forwards the incoming editor calls to the storage editor for modifying
the local tree, and merges the tree delta and text delta
transparently.

=cut

sub _path_inside {
    my ($path, $parent) = @_;
    return 1 if $path eq $parent;
    return substr ($path, 0, length ($parent)+1) eq "$parent/";
}

sub rename_check {
    my ($self, $path, $nocache) = @_;
    return $self->{rename_cache}{$path}
	if exists $self->{rename_cache}{$path};
    for (@{$self->{rename_map}}) {
	my ($from, $to) = @$_;
	if (_path_inside ($path, $from)) {
	    my $newpath = $path;
	    $newpath =~ s/^\Q$from\E/$to/;
	    $newpath = $self->rename_check ($newpath, 1);
	    $self->{rename_cache}{$path} = $newpath;
	    return $newpath;
	}
    }
    return $path;
}

sub _same_parent {
    my ($path1, $path2) = @_;
    $path1 =~ s|/[^/]*$|/|;
    $path2 =~ s|/[^/]*$|/|;
    return $path1 eq $path2;
}

sub open_root {
    my ($self, @arg) = @_;
    my $ret = $self->SUPER::open_root (@arg);
    $self->{opened_baton}{''} = $ret;
    return $ret;
}

our $AUTOLOAD;

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = $AUTOLOAD;
    my $class = ref ($self);
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;
    my $baton_at = $self->baton_at ($func);
    my ($renamed, $renamed_anchor);

    if ($baton_at == 1) {
	my $newpath = $self->rename_check ($arg[0]);
	if ($newpath ne $arg[0]) {
	    ++$renamed;
	    if (exists $self->{renamed}[$arg[1]]) {
	    }
	    else {
		++$renamed_anchor unless _same_parent ($newpath, $arg[0]);
	    }
	    $arg[0] = $newpath;
	}
    }

    my $sfunc = "SUPER::$func";
    my $ret = $self->$sfunc (@arg);

    $self->{renamed}[$ret]++ if $renamed;

    if ($renamed_anchor) {
	$self->{renamed_anchor}[$ret] = $self->{edit_tree}[$arg[1]][-1]
    }
    else {
	$self->{opened_baton}{$arg[0]} = $ret
	    if $func =~ m/^open/;
    }

    return $ret;
}

sub handle_rename_anchor {
    my ($self, $entry) = @_;
    my $path = $entry->[2];
    my $parent = $path;
    $parent =~ s|/[^/]*$|| or $parent = '';
    die "parent $parent (of $path) not opened" unless exists $self->{opened_baton}{$parent};
    my @newentry = @$entry;
    unshift @{$self->{edit_tree}[$self->{opened_baton}{$parent}]}, \@newentry;
    @$entry = [];
}

sub close_edit {
    my $self = shift;
    $self->SUPER::close_edit (@_);
    for (0..$#{$self->{renamed_anchor}}) {
	next unless defined $self->{renamed_anchor}[$_];
	$self->handle_rename_anchor ($self->{renamed_anchor}[$_]);
    }
    $self->drive ($self->{editor});
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
