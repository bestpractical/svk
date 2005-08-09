package SVK::Editor::Copy;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);

use SVK::Editor::Composite;
use SVK::Util qw( get_depot_anchor );

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

#    if (defined($path) && $self->incopy($path)) {
#	Carp::cluck "should ignore $path $pbaton";
#	return 1;
#    }

    return;
}

sub find_copy {
    my ($self, $path) = @_;
    my $base_path = File::Spec::Unix->catdir($self->{base_path}, $path);
    my $target_path = File::Spec::Unix->catdir($self->{src}{path}, $path);
    my ($toroot, $fromroot, $frompath) =
	SVK::Target::nearest_copy($self->{src}->root, $target_path);

    return unless defined $frompath;
    my ($base, $from, $to) = map {$_->revision_root_revision}
	($self->{base_root}, $fromroot, $toroot);
    if ($from <= $base && $base < $to &&
	$frompath =~ m{^\Q$self->{base_path}/}) { # within the anchor
	warn "==> $path is copied from $frompath:$from" if $main::DEBUG;
	if (($frompath, $from) = $self->{cb_resolve_copy}->($frompath, $from)) {
	    push @{$self->{incopy}}, { path => $path, frompath => $frompath };
	    warn "==> resolved to $frompath:$from" if $main::DEBUG;
	    return $self->{cb_copyfrom}->($frompath, $from);
	}
    }
    return;
}

sub incopy {
    my ($self, $path) = @_;
    return unless exists $self->{incopy}[-1];
    return $path =~ m{^\Q$self->{incopy}[-1]{path}\E/};
}

sub outcopy {
    my ($self, $path) = @_;
    return unless exists $self->{incopy}[-1];
    return unless $self->{incopy}[-1]{path} eq $path;
    pop @{$self->{incopy}};
}

sub add_directory {
    my ($self, $path, $pbaton, $from_path, $from_rev, $pool) = @_;
    return $self->{ignore_baton} if $self->should_ignore($path, $pbaton);

    if (my @ret = $self->find_copy($path)) {
	my $anchor_baton = $self->SUPER::add_directory($path, $pbaton, @ret, $pool);
	
	# XXX
	$self->{incopy}[-1]{baton} = $anchor_baton;
	return $self->{ignore_baton}
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

    if (my @ret = $self->find_copy($path)) {
	# turn into replace
	$self->SUPER::delete_entry($path, $arg[0], $pbaton, $arg[1]);
	warn "==> to add with history ".join(',', $self, $path, $pbaton, @ret, $arg[1]) if $main::DEBUG;

	my ($anchor, $target) = get_depot_anchor(1, $path);
	my $file_baton = $self->SUPER::add_file($path, $pbaton, @ret, $arg[1]);
	my ($src_anchor, $src_target) = get_depot_anchor(1, $self->{incopy}[-1]{frompath});
	# it's probably easier to just generate the textdelta ourselves
	# but it should be reused in add_directory copy as well
	my $editor = SVK::Editor::Composite->new
	    ( target => $target, target_baton => $file_baton,
	      anchor => $anchor, anchor_baton => $pbaton,
	      master_editor => $self,
	    );

	my ($src_path, $src_rev) = @ret;
	SVK::XD->depot_delta
		( oldroot => $self->{base_root}->fs->revision_root($src_rev),
		  newroot => $self->{dst}->root,
		  oldpath => [$src_anchor, $src_target],
		  newpath => File::Spec::Unix->catdir($self->{dst}{path}, $path),
		  editor =>
		  SVK::Editor::Translate->new
		  (_editor => [$editor],
		   translate => sub { $_[0] =~ s/^\Q$src_target/$target/ },
		  )
		);
	# close file is done by the delta;
	return $self->{ignore_baton};
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
    return $self->SUPER::delete_entry($path, $revision, $pdir, @arg);
}

sub close_directory {
    my ($self, $path, @arg) = @_;
    return if $self->should_ignore(undef, $path);
    $self->outcopy($path);
    $self->SUPER::close_directory($path, @arg);
}

1;
