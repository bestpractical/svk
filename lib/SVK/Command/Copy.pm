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
    $arg[1] = '' if $#arg < 1;
    return ((map {$self->arg_depotpath ($_)} @arg[0..$#arg-1]),
	    $self->arg_co_maybe ($arg[-1]));
}

sub lock {
    my $self = shift;
    $_[-1]->{copath} ? $self->lock_target ($_[-1]) : $self->lock_none;
}

sub do_copy_direct {
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

sub do_copy_co {
    my ($self, $src, $dst) = @_;
    my $xdroot = $dst->root ($self->{xd});
    if (-d $dst->{copath}) {
	# XXX: proper descendent
	my ($name) = $src->{depotpath} =~ m|(/[^/]+)/?$|;
#	$dst = $self->arg_copath ("$dst->{depotpath}$name");
	$dst->{depotpath} .= $name;
	$dst->{path} .= $name;
	$dst->{copath} .= $name;
    }
    my $copath = $dst->{copath};
    $src->anchorify; $dst->anchorify;
    SVK::Merge->new (%$self, repos => $dst->{repos}, nodelay => 1,
		     report => $dst->{report},
		     base => $src->new (path => '/', revision => 0),
		     src => $src, dst => $dst)->run ($self->get_editor ($dst));

    $self->{xd}{checkout}->store_recursively ($copath, {'.schedule' => undef,
							'.newprop' => undef});
    $self->{xd}{checkout}->store ($copath, {'.schedule' => 'add',
					    scheduleanchor => $copath,
					    '.copyfrom' => $src->path,
					    '.copyfrom_rev' => $src->{revision}});
}

sub run {
    my ($self, @src) = @_;
    my $dst = pop @src;
    die loc("repos paths mismatch") unless $dst->same_repos (@src);
    if (defined $self->{rev}) {
	$_->{revision} = $self->{rev} for @src;
    }
    my $fs = $dst->{repos}->fs;
    if ($dst->{copath}) {
	# XXX: check if dst is versioned
	die loc("%1 is not a directory.", $dst->{copath})
	    if $#src > 0 && !-d $dst->{copath};
	$self->do_copy_co ($_, $dst->new) for @src;
    }
    else {
	die loc("Can't copy more than one depotpath to depotpath")
	    if $#src > 0;
	return unless $self->check_mirrored_path ($dst);
	$self->get_commit_message ();
	$self->do_copy_direct ( author => $ENV{USER},
				%{$src[0]},
				dpath => $dst->{path},
				%$self,
			      );
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
