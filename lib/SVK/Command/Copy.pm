package SVK::Command::Copy;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Commit );
use SVK::Util qw( get_anchor );
use SVK::I18N;

sub options {
    ($_[0]->SUPER::options,
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;
    return (map {$self->arg_co_maybe ($_)} @arg);
}

sub lock {
    my $self = shift;
    $_[-1]->{copath} ? $self->lock_target ($_[-1]) : $self->lock_none;
}

sub do_copy_direct {
    # OBSOLETED
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $edit = $self->get_commit_editor ($fs->revision_root ($fs->youngest_rev),
					 sub { print loc("Committed revision %1.\n", $_[0]) },
					 '/', %arg);
    # XXX: check parent, check isfile, check everything...
    $edit->open_root();
    $edit->copy_directory ($arg{dpath}, "file://$arg{repospath}$arg{path}",
			   $arg{revision});
    $edit->close_edit();
}

sub handle_co_item {
    my ($self, $src, $dst) = @_;
    $src->depotpath;
    my $xdroot = $dst->root ($self->{xd});
    if (-d $dst->{copath}) {
	$dst->descend ($src->{path} =~ m|/([^/]+)/?$|);
    }
    die loc ("Path %1 already exists.\n", $dst->{copath})
	if -e $dst->{copath};
    my ($copath, $report) = @{$dst}{qw/copath report/};
    $src->anchorify; $dst->anchorify;
    # if SVK::Merge could take src being copath to do checkout_delta
    # then we have 'svk cp copath... copath' for free.
    SVK::Merge->new (%$self, repos => $dst->{repos}, nodelay => 1,
		     report => $report,
		     base => $src->new (path => '/', revision => 0),
		     src => $src, dst => $dst)->run ($self->get_editor ($dst));

    $self->{xd}{checkout}->store_recursively ($copath, {'.schedule' => undef,
							'.newprop' => undef});
    $self->{xd}{checkout}->store ($copath, {'.schedule' => 'add',
					    scheduleanchor => $copath,
					    '.copyfrom' => $src->path,
					    '.copyfrom_rev' => $src->{revision}});
}

sub handle_direct_item {
    my ($self, $editor, $m, $src, $dst) = @_;
    $src->normalize;
    my ($path, $rev) = @{$src}{qw/path revision/};
    if ($m) {
	$path =~ s/^\Q$m->{target_path}\E/$m->{source}/;
	$rev = $m->find_remote_rev ($rev)
	    or die "Can't find remote revision of for $path";
    }
    else {
	$path = "file://$src->{repospath}$path";
    }
    my $dstpath = $dst->path;
    $dstpath =~ s|^\Q$m->{target_path}\E/?|| if $m;
    $editor->close_directory
	($editor->add_directory ($dstpath, 0, $path, $rev));
    $editor->adjust_anchor ($editor->{edit_tree}[0][-1]);
}

sub _unmodified {
    my ($self, $target) = @_;
    $target->anchorify;
    $self->{xd}->checkout_delta
	( %$target,
	  xdroot => $target->root ($self->{xd}),
	  editor => SVK::Editor::Status->new
	  ( notify => SVK::Notify->new
	    ( cb_flush => sub {
		  die loc ("%1 is modified.\n", $target->copath ($_[0]));
	      })),
	  cb_unknown => sub {
	      die loc ("%1 is missing.\n", $target->copath ($_[0]))});
}

sub check_src {
    my ($self, @src) = @_;
    for my $src (@src) {
	# XXX: respect copath rev
	$src->{revision} = $self->{rev} if defined $self->{rev};
	next unless $src->{copath};
	$self->_unmodified ($src->new);
    }
}

sub run {
    my ($self, @src) = @_;
    my $dst = pop @src;
    return loc("Different depots.\n") unless $dst->same_repos (@src);
    my $m = $self->under_mirror ($dst);
    return "Different sources.\n"
	if $m && !$dst->same_source (@src);
    $self->check_src (@src);
    my $fs = $dst->{repos}->fs;
    if ($dst->{copath}) {
	# XXX: check if dst is versioned
	return loc("%1 is not a directory.\n", $dst->{copath})
	    if $#src > 0 && !-d $dst->{copath};
	$self->handle_co_item ($_, $dst->new) for @src;
    }
    else {
	$self->get_commit_message ();
	my $root = $dst->root;
	if ($root->check_path ($dst->{path}) != $SVN::Node::dir) {
	    die loc ("Copying more than one source requires %1 to be directory.\n", $dst->{report})
		if $#src > 0;
	    $dst->anchorify;
	}
	my ($storage, %cb) = $self->get_editor ($dst->new (path => $m ? $m->{target_path} : '/'));
	my $editor = SVK::Editor::Rename->new ( editor => $storage );
	my $baton = $editor->open_root ($cb{cb_rev}->(''));
	for (@src) {
	    $self->handle_direct_item ($editor, $m, $_,
				       $dst->{targets} ? $dst :
				       $dst->new (targets => [$_->{path} =~ m|/([^/]+)/?$|]));
	}
	$editor->close_directory ($baton);
	$editor->close_edit;
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Copy - Make a versioned copy

=head1 SYNOPSIS

 copy DEPOTPATH1 DEPOTPATH2
 copy DEPOTPATH1 PATH

=head1 OPTIONS

 -m [--message] arg:     Needs description
 -C [--check-only]:      Needs description
 -s [--sign]:            Needs description
 -r [--revision] arg:    Needs description
 --force:                Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
