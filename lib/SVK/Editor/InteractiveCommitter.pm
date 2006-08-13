package SVK::Editor::InteractiveCommitter;

use strict;
use SVK::I18N;
use SVN::Delta;

use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'SVK::Editor';

sub new {
    my ($class) = shift;
    
    my $self = $class->SUPER::new(@_);
       
    return $self;
}

sub _action {
  my ($self, $path) = @_;

  return unless defined $path;
  my $ret = $self->{status}{info}{$path};
  #Carp::cluck $path unless $ret;
  return $ret;
}

sub close_edit {
    my ($self, $pool) = @_;
    
    return $self->{storage}->close_edit($pool);
}

sub abort_edit {
    my ($self, $pool) = @_;

    $self->{storage}->abort_edit($pool);
}

sub open_root {
    my ($self, $baserev, $pool) = @_;

    $self->{storage_baton}{''} =
        $self->{storage}->open_root($baserev, $pool);

    return '';
}

sub add_file {
    my ($self, $path, $pdir, $copy_path, $rev, $pool) = @_;

    my $action = $self->_action($path) or return;
    $self->{storage_baton}{$path} = $action->on_add_file_commit(@_)
        if $action->enabled;
    
    return $path;
}

sub open_file {
    my ($self, $path, $pdir, $rev, $pool) = @_;

    my $action = $self->_action($path) or return;

    $self->{storage_baton}{$path} = $action->on_open_file_commit(@_);

    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum, $pool) = @_;
    my $action = $self->_action($path) or return;
    
    return $action->on_apply_textdelta_commit(@_);
}

sub change_file_prop {
    my ($self, $path, $name, $value, $pool) = @_;

    my $action = $self->_action($path) or return;
    $action = $action->{props}{$name};
    return unless $action->enabled;
    $action->on_change_file_prop_commit(@_);
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    my $action = $self->_action($path) or return;

    $action->on_close_file_commit(@_) if $action->enabled;
    delete $self->{status}{info}{$path};
}

sub delete_entry {
    my ($self, $path, $rev, $pdir, $pool) = @_;

    my $action = $self->_action($path) or return;
    $action->on_delete_entry_commit(@_);
}

sub add_directory {
    my ($self, $path, $pdir, $copy_from, $rev, $pool) = @_;

    my $action = $self->_action($path) or return;

    $self->{storage_baton}{$path} = $action->on_add_directory_commit(@_)
	if $action->enabled;

    return $path;
}

sub open_directory {
    my ($self, $path, $pdir, $rev, $pool) = @_;

    my $action = $self->_action($path) or return;

    $self->{storage_baton}{$path} = $action->on_open_directory_commit(@_);

    return $path;
}

sub change_dir_prop {
    my ($self, $path, $name, $value, $pool) = @_;

    my $action = $self->_action($path) or return;
    $action = $action->{props}{$name};
    
    return unless $action->enabled;
    $action->on_change_dir_prop_commit(@_);
}

sub close_directory {
    my ($self, $path) = @_;
    my $action = $self->_action($path) or return;

    $action->on_close_directory_commit(@_);
    delete $self->{status}{info}{$path};
}

sub conflict {
    my ($self, $path) = @_;

    $self->{conflicts} ||= $self->{status}{conflicts};
    push @{$self->{conflicts}}, $path;
}

1;

