package SVK::DelayEditor;
use strict;
our $VERSION = '0.12';
our @ISA = qw(SVN::Delta::Editor);

sub _open_pdir {
    my ($self, $pbaton) = @_;
    my $baton;

    unless ($self->{opened}{$pbaton}) {
	my ($path, $ppbaton, @arg) = @{$self->{batoninfo}{$pbaton}};
	$self->{batons}{$pbaton} = $self->SUPER::open_directory
	    ($path, $self->_open_pdir ($ppbaton), @arg);
	$self->{opened}{$pbaton} = 1;
    }

    return $self->{batons}{$pbaton};
}

sub open_root {
    my ($self, @arg) = @_;
    $self->{nbaton} = 0;
    $self->{batons}{$self->{nbaton}} = $self->SUPER::open_root (@arg);
    $self->{opened}{$self->{nbaton}} = 1;
    return $self->{nbaton}++;
}

sub add_file {
    my ($self, $path, $pbaton, @arg) = @_;
    $self->SUPER::add_file ($path, $self->_open_pdir ($pbaton), @arg);
}

sub open_file {
    my ($self, $path, $pbaton, @arg) = @_;
    $self->SUPER::open_file ($path, $self->_open_pdir ($pbaton), @arg);
}

sub add_directory {
    my ($self, $path, $pbaton, @arg) = @_;
    my $baton = $self->SUPER::add_directory ($path, $self->_open_pdir ($pbaton), @arg);
    $self->{batons}{$self->{nbaton}} = $baton;
    $self->{opened}{$self->{nbaton}} = 1;
    return $self->{nbaton}++;
}

sub delete_entry {
    my ($self, $path, $rev, $pbaton, $pool) = @_;
    $self->SUPER::delete_entry ($path, $rev, $self->_open_pdir ($pbaton), $pool);
}

sub change_dir_prop {
    my ($self, $baton, @arg) = @_;
    $self->SUPER::change_dir_prop ($self->_open_pdir ($baton), @arg);
}

sub open_directory {
    my ($self, $path, $pbaton, @arg) = @_;
    $self->{batoninfo}{$self->{nbaton}} = [$path, $pbaton, @arg];
    return $self->{nbaton}++;
}

sub close_directory {
    my ($self, $baton, $pool) = @_;
    if ($self->{opened}{$baton}) {
	$self->SUPER::close_directory ($self->{batons}{$baton}, $pool);
	delete $self->{opened}{$baton};
    }
    delete $self->{batons}{$baton};
    delete $self->{batoninfo}{$baton};
}

1;

