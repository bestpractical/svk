package SVK::DelayEditor;
use strict;
our $VERSION = '0.12';
our @ISA = qw(SVN::Delta::Editor);

sub _latest_baton {
    my ($self) = @_;
    return (@{$self->{bstack}} && $self->{bstack}[-1][0]) || ($self->{root});
}

sub _open_pdir {
    my ($self) = @_;
    my $baton;
    for (@{$self->{stack}}) {
	my ($path, $pbaton, @arg) = @$_;
	$baton = $self->SUPER::open_directory ($path, $pbaton || $self->_latest_baton, @arg);
	push @{$self->{bstack}}, [$baton, $arg[-1]];
    }
    @{$self->{stack}} = ();
    return $self->_latest_baton;
}

sub open_root {
    my ($self, @arg) = @_;
    $self->{bstack} = [];
    $self->{stack} = [];
    $self->{root} = $self->SUPER::open_root (@arg);
}

sub add_file {
    my ($self, $path, $pbaton, @arg) = @_;
    $self->SUPER::add_file ($path, $self->_open_pdir, @arg);
}

sub open_file {
    my ($self, $path, $pbaton, @arg) = @_;
    $self->SUPER::open_file ($path, $self->_open_pdir, @arg);
}

sub add_directory {
    my ($self, $path, $pbaton, @arg) = @_;
    my $baton = $self->SUPER::add_directory ($path, $self->_open_pdir, @arg);
    push @{$self->{bstack}}, [$baton, $arg[-1]];
    return $baton;
}

sub delete_entry {
    my ($self, $path, $rev, $pbaton, $pool) = @_;
    $self->SUPER::delete_entry ($path, $rev, $self->_open_pdir, $pool);
}

sub change_dir_prop {
    my ($self, $baton, @arg) = @_;
    $self->SUPER::change_dir_prop ($self->_open_pdir, @arg);
}

sub open_directory {
    my ($self, $path, @arg) = @_;
    push @{$self->{stack}}, [$path, @arg];
    return undef;
}

sub close_directory {
    my ($self, @arg) = @_;
    if (@{$self->{stack}}) {
	pop @{$self->{stack}};
    }
    elsif (my $now = pop @{$self->{bstack}}) {
	$self->SUPER::close_directory (@$now);
    }
    else {
	$self->SUPER::close_directory (@arg);
    }
}

1;

