package SVK::Editor::Delay;
use strict;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVN::Delta::Editor);

sub _open_pbaton {
    my ($self, $pbaton, $func) = @_;
    my $baton;

    $func = "SUPER::open_$func";
    unless ($self->{opened}{$pbaton}) {
	my ($path, $ppbaton, @arg) = @{$self->{batoninfo}{$pbaton}};
	$self->{batons}{$pbaton} = $self->$func
	    ($path, $self->_open_pdir ($ppbaton), @arg);
	$self->{opened}{$pbaton} = 1;
    }

    return $self->{batons}{$pbaton};
}

sub _close_baton {
    my ($self, $func, $baton, $pool) = @_;
    $func = "SUPER::close_$func";
    if ($self->{opened}{$baton}) {
	$self->$func ($self->{batons}{$baton}, $pool);
	delete $self->{opened}{$baton};
    }
    delete $self->{batons}{$baton};
    delete $self->{batoninfo}{$baton};
}

sub _open_pdir { _open_pbaton (@_, 'directory') }
sub _open_file { _open_pbaton (@_, 'file') }

sub open_root {
    my ($self, @arg) = @_;
    $self->{nbaton} = 0;
    $self->{batons}{$self->{nbaton}} = $self->SUPER::open_root (@arg);
    $self->{opened}{$self->{nbaton}} = 1;
    return $self->{nbaton}++;
}

sub add_file {
    my ($self, $path, $pbaton, @arg) = @_;
    my $baton = $self->SUPER::add_file ($path, $self->_open_pdir ($pbaton), @arg);
    $self->{batons}{$self->{nbaton}} = $baton;
    $self->{opened}{$self->{nbaton}} = 1;
    return $self->{nbaton}++;
}

sub open_file {
    my ($self, $path, $pbaton, @arg) = @_;
    $self->{batoninfo}{$self->{nbaton}} = [$path, $pbaton, @arg];
    return $self->{nbaton}++;
}

sub apply_textdelta {
    my ($self, $baton, @arg) = @_;
    return $self->SUPER::apply_textdelta ($self->_open_file ($baton), @arg);
}

sub change_file_prop {
    my ($self, $baton, @arg) = @_;
    return $self->SUPER::change_file_prop ($self->_open_file ($baton), @arg);
}

sub close_file {
    my $self = shift;
    $self->_close_baton ('file', @_);
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
    my $self = shift;
    $self->_close_baton ('directory', @_);
}

1;

