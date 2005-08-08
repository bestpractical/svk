package SVK::Editor::Copy;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
use SVK::Editor::Composite;
our @ISA = qw(SVN::Delta::Editor);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{ignore_baton} = \(my $dummy);
    return $self;
}

sub should_ignore {
    my ($self, $path, $pbaton) = @_;
    if (defined $pbaton && $pbaton eq $self->{ignore_baton}) {
	return 1;
    }

    if (defined($path) && $self->incopy($path)) {
	return 1;
    }

    return;
}

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
	warn "==> $path is copied from $frompath:$from" if $main::DEBUG;
	if (($frompath, $from) = $self->{cb_resolve_copy}->($frompath, $from)) {
	    push @{$self->{incopy}}, $path;
	    warn "==> resolved to $frompath:$from" if $main::DEBUG;
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
    return $self->{ignore_baton} if $self->should_ignore($path, $pbaton);

    if (my @ret = $self->find_copy($path)) {
	my $anchor_baton = $self->SUPER::add_directory($path, $pbaton, @ret, $pool);

	return $anchor_baton;
	# maybe just close_directory here and
	# return undef. so others can just check pbaton being
	# undef
    }

    $self->SUPER::add_directory($path, $pbaton, $from_path, $from_rev, $pool);
}

sub add_file {
    my ($self, $path, $pbaton, @arg) = @_;
    return $self->{ignore_baton} if $self->should_ignore($path, $pbaton);

    $self->find_copy($path);

    $self->SUPER::add_file($path, $pbaton, @arg);
}

sub open_file {
    my ($self, $path, $pbaton, @arg) = @_;
    return $self->{ignore_baton} if $self->should_ignore($path, $pbaton);

    warn "==> might be evil" if $main::DEBUG;
    if (my @ret = $self->find_copy($path)) {
	# turn into replace
	warn "==> evil! $path" if $main::DEBUG;
	$self->SUPER::delete_entry($path, $arg[0], $pbaton, $arg[1]);
	my $anchor_baton = $self->SUPER::add_file($path, $pbaton, @ret, $arg[1]);
	return $anchor_baton;
    }

    $self->SUPER::open_file($path, $pbaton, @arg);
}

sub apply_textdelta {
    my ($self, $path, @arg) = @_;
    return if $self->should_ignore(undef, $path);
    return $self->SUPER::apply_textdelta($path, @arg);
}

sub close_file {
    my ($self, $path, @arg) = @_;
    return if $self->should_ignore(undef, $path);
    $self->outcopy($path);
    return $self->SUPER::close_file($path, @arg);
}


sub change_file_prop {
    my ($self, $path, @arg) = @_;
    return if $self->should_ignore(undef, $path);

    return $self->SUPER::change_file_prop($path, @arg);
}

sub change_dir_prop {
    my ($self, $path, @arg) = @_;
    return if $self->should_ignore(undef, $path);

    return $self->SUPER::change_dir_prop($path, @arg);

}

sub delete_entry {
    my ($self, $path, $revision, $pdir, @arg) = @_;
    return if $self->should_ignore($path, $pdir);
    return $self->SUPER::delete_entry($self, $path, $revision, $pdir, @arg);
}

sub close_directory {
    my ($self, $path, @arg) = @_;
    return if $self->should_ignore(undef, $path);
    $self->outcopy($path);
    $self->SUPER::close_directory($path, @arg);
}

1;
