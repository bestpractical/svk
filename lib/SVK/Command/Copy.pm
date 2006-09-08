package SVK::Command::Copy;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Mkdir );
use SVK::Util qw( get_anchor get_prompt abs2rel splitdir is_uri make_path );
use SVK::I18N;

sub options {
    ($_[0]->SUPER::options,
     'q|quiet'         => 'quiet',
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if @arg < 1;

    push @arg, '' if @arg == 1;

    my $dst = pop(@arg);
    die loc ("Copy destination can't be URI.\n")
	if is_uri ($dst);

    die loc ("More than one URI found.\n")
	if (grep {is_uri($_)} @arg) > 1;
    my @src;

    if ( my $target = eval { $self->{xd}->target_from_copath_maybe($dst) }) {
        $dst = $target;
	# don't allow new uri in source when target is copath
	@src = (map {$self->arg_co_maybe
			 ($_, $dst->isa('SVK::Path::Checkout')
			  ? loc ("path '%1' is already a checkout", $dst->report)
			  : undef)} @arg);
    }
    else {
	@src = (map {$self->arg_co_maybe ($_)} @arg);
        # Asking the user for copy destination.
        # In this case, first magically promote ourselves to "cp -p".
        # (otherwise it hurts when user types //deep/directory/name)
        $self->{parent} = 1;

        # -- make a sane default here for mirroring --
        my $default = undef;
        if (@src == 1 and $src[0]->path =~ m{/mirror/([^/]+)$}) {
            $default = "/" . $src[0]->depotname . "/$1";
        }

        my $path = $self->prompt_depotpath("copy", $default);

        if ($dst eq '.') {
            $self->{_checkout_path} = (splitdir($path))[-1];
        }
        else {
            $self->{_checkout_path} = $dst;
        }

        $dst = $self->arg_depotpath("$path/");
    }

    return (@src, $dst);
}

sub lock {
    my $self = shift;
    $self->lock_coroot($_[-1]);
}

sub handle_co_item {
    my ($self, $src, $dst) = @_;
    $src = $src->as_depotpath;
    die loc ("Path %1 does not exist.\n", $src->path_anchor)
	if $src->root->check_path ($src->path_anchor) == $SVN::Node::none;
    my ($copath, $report) = ($dst->copath, $dst->report);
    die loc ("Path %1 already exists.\n", $copath)
	if -e $copath;
    my ($entry, $schedule) = $self->{xd}->get_entry($copath);
    $src->normalize; $src->anchorify;
    $self->ensure_parent($dst);
    $dst->anchorify;

    my $notify = $self->{quiet} ? SVK::Notify->new(quiet => 1) : undef;
    # if SVK::Merge could take src being copath to do checkout_delta
    # then we have 'svk cp copath... copath' for free.
    # XXX: use editor::file when svkup branch is merged
    my ($editor, $inspector, %cb) = $dst->get_editor
	( ignore_checksum => 1, quiet => 1,
	  check_only => $self->{check_only},
	  update => 1, ignore_keywords => 1,
	);
    SVK::Merge->new (%$self, repos => $dst->repos, nodelay => 1,
		     report => $report, notify => $notify,
		     base => $src->new (path => '/', revision => 0),
		     src => $src, dst => $dst)
	    ->run
		($editor, %cb, inspector => $inspector);

    $self->{xd}{checkout}->store
	($copath, { revision => undef });
    # XXX: can the schedule be something other than delete ?
    $self->{xd}{checkout}->store ($copath, {'.schedule' => $schedule ? 'replace' : 'add',
					    scheduleanchor => $copath,
					    '.copyfrom' => $src->path,
					    '.copyfrom_rev' => $src->revision});
}

sub handle_direct_item {
    my ($self, $editor, $anchor, $m, $src, $dst, $other_call) = @_;
    $src->normalize;
    # if we have targets, ->{path} must exist
    if (!$self->{parent} && $dst->{targets} && !$dst->root->check_path ($dst->path_anchor)) {
	die loc ("Parent directory %1 doesn't exist, use -p.\n", $dst->report);
    }
    my ($path, $rev) = ($src->path_anchor, $src->revision);
    if ($m) {
	$path =~ s/^\Q$m->{target_path}\E/$m->{source}/;
        if (my $remote_rev = $m->find_remote_rev($rev)) {
            $rev = $remote_rev;
        } else {
            die "Can't find remote revision of local revision $rev for $path";
        }
    }
    else {
	$path = "file://$src->{repospath}$path";
    }
    my $baton = $editor->add_directory (abs2rel ($dst->path, $anchor => undef, '/'), 0, $path, $rev);
    $other_call->($baton) if $other_call;
    $editor->close_directory($baton);
    $self->adjust_anchor ($editor);
}

sub _unmodified {
    my ($self, $target) = @_;
    my (@modified, @unknown);
    $target = $self->{xd}->target_condensed($target); # anchor
    $self->{xd}->checkout_delta
	( $target->for_checkout_delta,
	  xdroot => $target->create_xd_root,
	  editor => SVK::Editor::Status->new
	  ( notify => SVK::Notify->new
	    ( cb_flush => sub { push @modified, $_[0] })),
	  cb_unknown => sub { push @unknown, $_[1] } );

    if (@modified || @unknown) {
	my @reports = sort map { loc ("%1 is modified.\n", $target->report_copath ($_)) } @modified;
	push @reports, sort map { loc ("%1 is unknown.\n", $target->report_copath ($_)) } @unknown;
	die join("", @reports);
    }
}

sub check_src {
    my ($self, @src) = @_;
    for my $src (@src) {
	# XXX: respect copath rev
	$src->revision($self->{rev}) if defined $self->{rev};
	next unless $src->isa('SVK::Path::Checkout');
	$self->_unmodified ($src->new);
    }
}

sub run {
    my ($self, @src) = @_;
    my $dst = pop @src;

    return loc("Different depots.\n") unless $dst->same_repos (@src);
    my $m = $self->under_mirror ($dst);
    return loc("Different sources.\n")
	if $m && !$dst->same_source (@src);
    $self->check_src (@src);
    # XXX: check dst to see if the copy is obstructured or missing parent
    my $fs = $dst->repos->fs;
    if ($dst->isa('SVK::Path::Checkout')) {
	return loc("%1 is not a directory.\n", $dst->report)
	    if $#src > 0 && !-d $dst->copath;
	return loc("%1 is not a versioned directory.\n", $dst->report)
	    if -d $dst->copath && $dst->root->check_path($dst->path) != $SVN::Node::dir;

	my @cpdst;
	for (@src) {
	    my $cpdst = $dst->new;
	    # implicit target for "cp x y z dir/"
	    if (-d $cpdst->copath) {
		# XXX: _path_inside should be refactored in to SVK::Util
		if ( substr($cpdst->path_anchor, 0, length($_->path_anchor)+1) eq $_->path_anchor."/") {
		    die loc("Invalid argument: copying directory %1 into itself.\n", $_->report);
		}
		if ($_->path_anchor eq $cpdst->path_anchor) {
		    print loc("Ignoring %1 as source.\n", $_->report);
		    next;
		}
		$cpdst->descend ($_->path_anchor =~ m|/([^/]+)/?$|)
	    }
	    die loc ("Path %1 already exists.\n", $cpdst->report)
		if -e $cpdst->copath;
	    push @cpdst, [$_, $cpdst];
	}
	$self->handle_co_item(@$_) for @cpdst;
    }
    else {
	if ($dst->root->check_path($dst->path_anchor) != $SVN::Node::dir) {
	    die loc ("Copying more than one source requires %1 to be directory.\n", $dst->report)
		if $#src > 0;
	    $dst->anchorify;
	}
	$self->get_commit_message ();
	my ($anchor, $editor) = $self->get_dynamic_editor ($dst);
	for (@src) {
	    $self->handle_direct_item ($editor, $anchor, $m, $_,
				       $dst->{targets} ? $dst :
				       $dst->new (targets => [$_->path_anchor =~ m|/([^/]+)/?$|]));
	}
	$self->finalize_dynamic_editor ($editor);
    }

    if (defined( my $copath = $self->{_checkout_path} )) {
        my $checkout = $self->command ('checkout');
	$checkout->getopt ([]);
        my @arg = $checkout->parse_arg ('/'.$dst->depotname.$dst->path, $copath);
        $checkout->lock (@arg);
        $checkout->run (@arg);
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Copy - Make a versioned copy

=head1 SYNOPSIS

 copy DEPOTPATH1 DEPOTPATH2
 copy DEPOTPATH [PATH]

=head1 OPTIONS

 -r [--revision] REV    : act on revision REV instead of the head revision
 -p [--parent]          : create intermediate directories as required
 -q [--quiet]           : print as little as possible
 -m [--message] MESSAGE : specify commit message MESSAGE
 -F [--file] FILENAME   : read commit message from FILENAME
 --template             : use the specified message as the template to edit
 --encoding ENC         : treat -m/-F value as being in charset encoding ENC
 -P [--patch] NAME      : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -C [--check-only]      : try operation but make no changes
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
