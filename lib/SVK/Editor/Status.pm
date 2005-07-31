package SVK::Editor::Status;
use strict;
use SVN::Delta;
use SVK::Version;  our $VERSION = $SVK::VERSION;
our @ISA = qw(SVN::Delta::Editor);

sub new {
    my ($class, @arg) = @_;
    my $self = $class->SUPER::new (@arg);
    $self->{report} ||= '';
    $self->{notify} ||= SVK::Notify->new_with_report ($self->{report});
    return $self;
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{notify}->node_status ('', '');
    return '';
}

sub add_or_replace {
    my ($self, $path) = @_;
    if ($self->{notify}->node_status ($path)) {
	$self->{notify}->node_status ($path, 'R')
	    if $self->{notify}->node_status ($path) eq 'D';
    }
    else {
	$self->{notify}->node_status ($path, 'A');
    }
}

sub add_file {
    my ($self, $path, $pdir, @arg) = @_;
    $self->add_or_replace ($path);
    $self->{notify}->hist_status ($path, '+') if $arg[0];
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    $self->{notify}->node_status ($path, '')
	unless $self->{notify}->node_status ($path);
    return $path;
}

sub apply_textdelta {
    my ($self, $path) = @_;
    return undef if $self->{notify}->node_status ($path) eq 'R';
    $self->{notify}->node_status ($path, 'M')
	if !$self->{notify}->node_status ($path) || $self->{notify}->hist_status ($path);
    return undef;
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    $self->{notify}->prop_status ($path, 'M');
}

sub close_file {
    my ($self, $path) = @_;
    $self->{notify}->flush ($path);
}

sub absent_file {
    my ($self, $path) = @_;
    return if $self->{ignore_absent};
    $self->{notify}->node_status ($path, '!');
    $self->{notify}->flush ($path);
}

sub delete_entry {
    my ($self, $path) = @_;
    $self->{notify}->node_status ($path, 'D');
#    $self->{notify}->flush ($path);
}

sub add_directory {
    my ($self, $path, $pdir, @arg) = @_;
    $self->add_or_replace ($path);
    $self->{notify}->hist_status ($path, '+') if $arg[0];
    $self->{notify}->flush ($path, 1);
    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, $pool) = @_;
    $self->{notify}->node_status ($path, '')
	unless $self->{notify}->node_status ($path);
    return $path;
}

sub change_dir_prop {
    my ($self, $path, $name, $value) = @_;
    $self->{notify}->prop_status ($path, 'M');
}

sub close_directory {
    my ($self, $path) = @_;
    $self->{notify}->flush_dir ($path);
}

sub absent_directory {
    my ($self, $path) = @_;
    return if $self->{ignore_absent};
    $self->{notify}->node_status ($path, '!');
    $self->{notify}->flush ($path);
}

sub conflict {
    my ($self, $path) = @_;
    $self->{notify}->node_status ($path, 'C');
}

sub obstruct {
    my ($self, $path) = @_;
    $self->{notify}->node_status ($path, '~');
}

1;
