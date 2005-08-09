package SVK::Editor::Composite;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);

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
	return $self->{target_baton}
	    if defined $self->{target} && $arg[0] eq $self->{target};
	$arg[0] = length $arg[0] ?
	    "$self->{anchor}/$arg[0]" : $self->{anchor};
    }

    $self->{master_editor}->$func(@arg);
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

sub close_edit {}

1;
