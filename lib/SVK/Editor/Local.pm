package SVK::Editor::Local;
use strict;
use SVK::Editor::XD;
use SVK::Util qw (get_anchor md5_fh);
use SVK::I18N;
use File::Path;
use base qw(SVK::Editor::Checkout);
our $VERSION = $SVK::VERSION;

sub add_directory {
    my $self = shift;
    my ($path) = @_;
    $self->{notify}->node_status ($path, 'A');
    $self->SUPER::add_directory (@_);
}

sub add_file {
    my $self = shift;
    my ($path) = @_;
    $self->{notify}->node_status ($path, 'A');
    $self->SUPER::add_file (@_);
}

sub delete_entry {
    my $self = shift;
    $self->SUPER::delete_entry (@_);
    my $path = shift;
    $self->{notify}->node_status ($path, 'D');
}

sub close_file {
    my $self = shift;
    $self->SUPER::close_file (@_);
    my $path = shift;
    $self->{notify}->node_status ($path, 'U')
	unless $self->{notify}->node_status ($path);
}

sub close_directory {
    my $self = shift;
    $self->SUPER::close_directory (@_);
    my $path = shift;
    $self->{notify}->flush_dir ($path, 1);
}

1;
