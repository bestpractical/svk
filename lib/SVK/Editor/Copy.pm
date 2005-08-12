package SVK::Editor::Copy;
use strict;
use warnings;
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

    if (ref($pbaton) eq 'SVK::Editor::Copy::copied_directory') {
	return 1;
    }

    return;
}

sub find_copy {
    my ($self, $path) = @_;
    my $base_path = File::Spec::Unix->catdir($self->{base_path}, $path);
    my $target_path = File::Spec::Unix->catdir($self->{src}{path}, $path);

    my ($cur_root, $cur_path) = ($self->{src}->root, $target_path);

    my $copyboundry_rev = $self->{copyboundry_rev};
    # XXX: pool! clear!
    my $ppool = SVN::Pool->new;
    while (1) {
	my ($toroot, $fromroot, $src_frompath) =
	    SVK::Target::nearest_copy($cur_root, $cur_path, $ppool);

	warn "===> $cur_path => $src_frompath" if $main::DEBUG;
	return unless defined $src_frompath;
	# don't use the copy unless it's the actual copy point
	my ($actual_cpanchor) = $toroot->copied_from($cur_path);
	return if $actual_cpanchor == -1;

	my ($src_from, $to) = map {$_->revision_root_revision}
	    ($fromroot, $toroot);

	# XXX: copy from 3rd party branch directly within the same mirror
	# copy from the other branch directly
	if ($src_frompath =~ m{^\Q$self->{dst}{path}/}) {
	    push @{$self->{incopy}}, { path => $path,
				       fromrev => $src_from,
				       frompath => $src_frompath,
				       dst_fromrev => $src_from,
				       dst_frompath => $src_frompath };
	    return $self->{cb_copyfrom}->($src_frompath, $src_from);
	}

	return unless $src_frompath =~ m{^\Q$self->{src}{path}/};
	warn 
	"$cur_path, $src_frompath: if ($src_from <= $copyboundry_rev && $copyboundry_rev < $to &&  $src_frompath =~ m{^\Q$self->{src}{path}/})" if $main::DEBUG;
	return unless $copyboundry_rev < $to; # don't care, too early
	# XXX: Document this condition

	if ($src_from > $copyboundry_rev) {
	    my $id = $fromroot->node_id($src_frompath);
	    if ($self->{copyboundry_root}->check_path($src_frompath) &&
		SVN::Fs::check_related($id, $self->{copyboundry_root}->node_id($src_frompath))) {
		my $src = $self->{src}->new(revision => $copyboundry_rev, path => $src_frompath);
		$src->normalize;
		$src_from = $src->{revision};
	    }
	    else {
		($cur_root, $cur_path) = ($fromroot, $src_frompath);
		next;
	    }

	}

	warn "==> $path is copied from $src_frompath:$src_from" if $main::DEBUG;
	if (my ($frompath, $from) = $self->{cb_resolve_copy}->($src_frompath, $src_from)) {
	    push @{$self->{incopy}}, { path => $path,
				       fromrev => $src_from,
				       frompath => $src_frompath,
				       dst_frompath => $frompath,
				       dst_fromrev => $from
				     };
	    warn "==> resolved to $frompath:$from"
		if $main::DEBUG;
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
	return $self->replay_add_history('directory', $path, $pbaton,
					 @ret, $pool);
    }

    $self->SUPER::add_directory($path, $pbaton, $from_path, $from_rev, $pool);
}

sub add_file {
    my ($self, $path, $pbaton, $from_path, $from_rev, $pool) = @_;
    return $self->{ignore_baton} if $self->should_ignore($path, $pbaton);

    if (my @ret = $self->find_copy($path)) {
	return $self->replay_add_history('file', $path, $pbaton,
					 @ret, $pool);
    }

    $self->SUPER::add_file($path, $pbaton, $from_path, $from_rev, $pool);
}

sub open_directory {
    my ($self, $path, $pbaton, @arg) = @_;
    if (my @ret = $self->find_copy($path)) {
	# turn into replace
	$self->SUPER::delete_entry($path, $arg[0], $pbaton, $arg[1]);
	return $self->replay_add_history('directory', $path, $pbaton, @ret, $arg[1])
    }

    $self->SUPER::open_directory($path, $pbaton, @arg);
}

sub open_file {
    my ($self, $path, $pbaton, @arg) = @_;
    return $self->{ignore_baton} if $self->should_ignore($path, $pbaton);
    if (my @ret = $self->find_copy($path)) {
	# turn into replace
	$self->SUPER::delete_entry($path, $arg[0], $pbaton, $arg[1]);
	return $self->replay_add_history('file', $path, $pbaton, @ret, $arg[1])
    }

    $self->SUPER::open_file($path, $pbaton, @arg);
}

sub apply_textdelta {
    my ($self, $path, @arg) = @_;
    return if $self->should_ignore(undef, $path);
    return $self->SUPER::apply_textdelta($path, @arg);
}

sub close_file {
    my ($self, $baton, @arg) = @_;
    if (ref($baton) eq 'SVK::Editor::Copy::copied_directory') {
	$self->outcopy($baton->{path});
	return $self->SUPER::close_file($baton->{baton}, @arg);

    }
    return if $self->should_ignore(undef, $baton);

    return $self->SUPER::close_file($baton, @arg);
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
    my ($self, $baton, @arg) = @_;
    if (ref($baton) eq 'SVK::Editor::Copy::copied_directory') {
	$self->outcopy($baton->{path});
	return $self->SUPER::close_directory($baton->{baton}, @arg);
    }
    return if $self->should_ignore(undef, $baton);

    $self->SUPER::close_directory($baton, @arg);
}

sub replay_add_history {
    my ($self, $type, $path, $pbaton, $src_path, $src_rev, $pool) = @_;
    my $func = "SUPER::add_$type";
    my $baton = $self->$func($path, $pbaton, $src_path, $src_rev, $pool);

    my ($anchor, $target) = ($path, '');
    my ($src_anchor, $src_target) = ($self->{incopy}[-1]{frompath}, '');

    my %arg = ( anchor => $anchor, anchor_baton => $baton );
    if ($type eq 'file') {
	($anchor, $target) = get_depot_anchor(1, $anchor);
	($src_anchor, $src_target) = get_depot_anchor(1, $src_anchor);
	%arg = ( anchor => $anchor, anchor_baton => $pbaton,
		 target => $target, target_baton => $baton );
    }

    my $editor = SVK::Editor::Composite->new
	( master_editor => $self, %arg );

    $editor = SVK::Editor::Translate->new
	(_editor => [$editor],
	 translate => sub { $_[0] =~ s/^\Q$src_target/$target/ })
	    if $type eq 'file';

    warn "****==> to delta $src_anchor / $src_target @ $self->{incopy}[-1]{fromrev} vs $self->{src}{path} / $path" if $main::DEBUG;;
    SVK::XD->depot_delta
	    ( oldroot => $self->{copyboundry_root}->fs->
	      revision_root($self->{incopy}[-1]{fromrev}),
	      newroot => $self->{src}->root,
	      oldpath => [$src_anchor, $src_target],
	      newpath => File::Spec::Unix->catdir($self->{src}{path}, $path),
	      editor => SVK::Editor::Delay->new(_editor => [$editor]) );

    # close file is done by the delta;
    return bless { path => $path,
		   baton => $baton,
		 }, __PACKAGE__.'::copied_directory';

    $self->{ignore_baton};
}


1;
