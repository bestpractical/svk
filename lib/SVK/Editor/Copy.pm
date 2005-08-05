package SVK::Editor::Copy;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);

sub find_copy {
    my ($self, $path) = @_;
    my $base_path = File::Spec::Unix->catdir($self->{base_path}, $path);
    my $target_path = File::Spec::Unix->catdir($self->{target_path}, $path);
    my ($toroot, $fromroot, $frompath) =
	SVK::Target::nearest_copy($self->{target_root}, $target_path);

    return unless defined $frompath;
    my ($base, $from, $to) = map {$_->revision_root_revision}
	($self->{base_root}, $fromroot, $toroot);
    if ($from <= $base && $base < $to &&
	$frompath =~ m{^\Q$self->{base_path}/}) { # within the anchor
	warn "==> $path is copied from $frompath:$from";
	if (($frompath, $from) = $self->{cb_resolve_copy}->($frompath, $from)) {
	    push @{$self->{incopy}}, $path;
	    warn "==> resolved to $frompath:$from";
	    return ($frompath, $from);
	}
    }
    return;
}

sub incopy {
    my ($self, $path) = @_;
    return unless exists $self->{incopy}[-1];
    return $path =~ m{^\Q$self->{incopy}[-1]\E/};
}

sub outcopy {
    my ($self, $path) = @_;
    return unless exists $self->{incopy}[-1];
    pop @{$self->{incopy}}
	if $self->{incopy}[-1] eq $path;
}

sub add_directory {
    my ($self, $path, $pbaton, $from_path, $from_rev, $pool) = @_;
    return undef unless defined $pbaton;

    if ($self->incopy($path)) {
	return undef;
    }
    else {
	if (my @ret = $self->find_copy($path)) {
	    ($from_path, $from_rev) = @ret;
	    $from_path = $from_path;
	}
    }


    $self->SUPER::add_directory($path, $pbaton, $from_path, $from_rev, $pool);
}

sub add_file {
    my ($self, $path, $pbaton, @arg) = @_;
    return undef unless defined $pbaton;

    if ($self->incopy($path)) {
	return undef;
    }
    else {
	$self->find_copy($path);
    }

    $self->SUPER::add_file($path, $pbaton, @arg);
}

sub apply_textdelta {
    my ($self, $path, @arg) = @_;
    return unless defined $path;
    return $self->SUPER::apply_textdelta($path, @arg);
}

sub close_file {
    my ($self, $path, @arg) = @_;
    return unless defined $path;
    $self->outcopy($path);
    return $self->SUPER::close_file($path, @arg);
}


sub change_file_prop {
    my ($self, $path, @arg) = @_;
    return unless defined $path;

    return $self->SUPER::change_file_prop($path, @arg);
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
    return unless defined $path;

    return $self->SUPER::change_dir_prop($path, @arg);

}

sub close_directory {
    my ($self, $path, @arg) = @_;
    return unless defined $path;
    $self->outcopy($path);
    $self->SUPER::close_directory($path, @arg);
}

1;
