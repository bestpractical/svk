package SVK::Editor::Composite;
use strict;

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

    if ($func =~ m/^(?:add|open)/) {
	$arg[0] = length $arg[0] ? "$self->{anchor}/$arg[0]" : $self->{anchor};
    }

    $self->{master_editor}->can($func)->
	($self->{master_editor}, @_);
}

sub open_root {
    my ($self, $base_revision) = @_;
    return $self->{anchor_baton};
}

sub close_directory {
    my ($self, $baton, @arg) = @_;
    return if $baton eq $self->{anchor_baton};

    $self->{master_editor}->close_directory($baton, @arg);
}

1;
