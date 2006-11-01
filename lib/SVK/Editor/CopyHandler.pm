package SVK::Editor::CopyHandler;
use strict;
use warnings;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
use base 'SVK::Editor::ByPass';

=head1 NAME

SVK::Editor::CopyHandler - intercept copies in editor calls

=head1 SYNOPSIS

=cut

sub add_directory {
    my ($self, $path, $pbaton, $from_path, $from_rev, $pool) = @_;

    ($from_path, $from_rev) = $self->{cb_copy}->($self, $from_path, $from_rev);
    $self->SUPER::add_directory( $path, $pbaton, $from_path, $from_rev, $pool );
}

sub add_file {
    my ($self, $path, $pbaton, $from_path, $from_rev, $pool) = @_;

    ($from_path, $from_rev) = $self->{cb_copy}->($self, $from_path, $from_rev);
    $self->SUPER::add_file( $path, $pbaton, $from_path, $from_rev, $pool );
}

1;
