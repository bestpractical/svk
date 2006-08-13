package SVK::Editor::Composite;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base 'SVK::Editor';

=head1 NAME

SVK::Editor::Composite - composite editor

=head1 SYNOPSIS



=head1 DESCRIPTION

This editor is constructed with C<anchor> and C<anchor_baton>.  It
then takes incoming editor calls, replay to C<master_editor> with
paths prefixed with C<anchor>.

=cut

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = our $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]/;

    if ($func =~ m/^(?:add|open|delete)/) {
	return $self->{target_baton}
	    if defined $self->{target} && $arg[0] eq $self->{target};
	$arg[0] = length $arg[0] ?
	    "$self->{anchor}/$arg[0]" : $self->{anchor};
    }
    elsif ($func =~ m/^close_(?:file|directory)/) {
	if (defined $arg[0]) {
	    return if $arg[0] eq $self->{anchor_baton};
	    return if defined $self->{target_baton} &&
		$arg[0] eq $self->{target_baton};
	}
    }

    $self->{master_editor}->$func(@arg);
}

sub set_target_revision {}

sub open_root {
    my ($self, $base_revision) = @_;
    return $self->{anchor_baton};
}

sub close_edit {}

1;
