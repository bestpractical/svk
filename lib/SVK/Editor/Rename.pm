package SVK::Editor::Rename;
use strict;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVK::Editor::Patch);
use SVK::Editor::Patch;
use SVK::I18N;

=head1 NAME

SVK::Editor::Rename - An editor that translates editor calls for renamed entries

=head1 SYNOPSIS

  $editor = SVK::Editor::Rename->new
    ( editor => $next_editor,
      rename_map => \@rename_map
    );

=head1 DESCRIPTION

Given the rename_map, which is a list of [from, to] pairs for
translating path in editor calls, C<SVK::Editor::Rename> serialize the
calls and rearrange them for making proper calls to C<$next_editor>.

The translation of pathnames is done with iterating through the
C<@rename_map>, translate with the first match. Translation is redone
untill no match is found.

C<SVK::Editor::Rename> is a subclass of C<SVK::Editor::Patch>, which
serailizes incoming editor calls. Each baton opened is recorded in
C<$self->{opened_baton}>, which could be use to lookup with path names.

When a path is opened that should be renamed, it's recorded in
C<$self->{renamed_anchor}> for reanchoring the renamed result to
proper parent directory before calls are emitted to C<$next_editor>.

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
    $self->{opened_baton}{''} = [$ret, 0];
    return $ret;
}

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = our $AUTOLOAD;
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
	$self->{opened_baton}{$arg[0]} = [$ret, $arg[1]]
	    if $func =~ m/^open/;
    }

    return $ret;
}

sub open_parent {
    my ($self, $path) = @_;
    my $parent = $path;
    $parent =~ s|/[^/]*$|| or $parent = '';
    return @{$self->{opened_baton}{$parent}}
	if exists $self->{opened_baton}{$parent};

    my ($pbaton, $ppbaton) = $self->open_parent ($parent);

    ++$self->{batons};

    if ($self->{cb_exist} && !$self->{cb_exist}->($parent)) {
	unshift @{$self->{edit_tree}[$pbaton]},
	    [$self->{batons}, 'add_directory', $parent, $ppbaton, undef, -1];
    }
    else {
	unshift @{$self->{edit_tree}[$pbaton]},
	    [$self->{batons}, 'open_directory', $parent, $ppbaton, -1];
    }

    $self->{edit_tree}[$self->{batons}] = [[undef, 'close_directory', $self->{batons}]];
    $self->{opened_baton}{$parent} = [$self->{batons}, $pbaton];
    return ($self->{batons}, $pbaton);
}

sub adjust_anchor {
    my ($self, $entry) = @_;
    my $path = $entry->[2];
    my ($pbaton) = $self->open_parent ($path);
    my @newentry = @$entry;
    # move the call to a proper place
    unshift @{$self->{edit_tree}[$pbaton]}, \@newentry;
    $newentry[2+$self->baton_at ($entry->[1])] = $pbaton;
    @$entry = [];
}

sub close_edit {
    my $self = shift;
    $self->SUPER::close_edit (@_);
    for (0..$#{$self->{renamed_anchor}}) {
	next unless defined $self->{renamed_anchor}[$_];
	$self->adjust_anchor ($self->{renamed_anchor}[$_]);
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
