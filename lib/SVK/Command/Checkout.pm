package SVK::Command::Checkout;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Update );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( get_anchor abs_path move_path splitdir $SEP );
use File::Path;

sub options {
    ($_[0]->SUPER::options,
     'l|list' => 'list',
     'd|delete|detach' => 'detach',
     'export' => 'export',
     'relocate' => 'relocate');
}

sub parse_arg {
    my ($self, @arg) = @_;

    return undef if $self->{list};
    return (@arg ? @arg : '') if $self->{detach};
    return (@arg >= 2 ? @arg : ('', @arg)) if $self->{relocate};
    @arg or return;

    my $depotpath = $self->arg_uri_maybe ($arg[0]);
    die loc("don't know where to checkout %1\n", $arg[0]) unless $arg[1] || $depotpath->{path} ne '/';

    $arg[1] =~ s|/$|| if $arg[1];
    $arg[1] = (splitdir($depotpath->{path}))[-1]
        if !defined($arg[1]) or $arg[1] =~ /^\.?$/;

    return ($depotpath, $arg[1]);
}

sub lock {
    my ($self, $src, $dst) = @_;

    return if $self->{detach} or $self->{relocate}; # hold giant
    return $self->lock_none if $self->{list};

    my $abs_path = abs_path ($dst) or return;
    $self->{xd}->lock ($abs_path);
}

sub _remove_entry { {depotpath => undef, revision => undef} }

sub run {
    my ($self) = @_;

    # Dispatch to one of the three methods
    foreach my $op (qw( list detach relocate )) {
        $self->{$op} or next;
        goto &{ $self->can("_do_$op") };
    }

    # Defaults to _do_checkout
    goto &{ $self->can('_do_checkout') };
}

sub _do_detach {
    my ($self, $path) = @_;

    my @copath = $self->_find_copath($path)
        or die loc("'%1' is not a checkout path.\n", $path);

    my $checkout = $self->{xd}{checkout};
    foreach my $copath (sort @copath) {
        $checkout->store ($copath, _remove_entry);
        print loc("Checkout path '%1' detached.\n", $copath);
    }

    return;
}

sub _do_list {
    my ($self) = @_;
    my $map = $self->{xd}{checkout}{hash};
    my $fmt = "%-20s\t%-s\n";
    printf $fmt, loc('Depot Path'), loc('Path');
    print '=' x 60, "\n";
    print sort(map sprintf($fmt, $map->{$_}{depotpath}, $_), grep $map->{$_}{depotpath}, keys %$map);
    return;
}

sub _do_relocate {
    my ($self, $path, $report) = @_;

    my @copath = $self->_find_copath($path)
        or die loc("'%1' is not a checkout path.\n", $path);
    @copath == 1
        or die loc("'%1' maps to multiple checkout paths.\n", $path);

    my $target = abs_path ($report);
    if (defined $target) {
        my ($entry, @where) = $self->{xd}{checkout}->get ($target);
        die loc("Overlapping checkout path is not supported (%1); use 'svk checkout --detach' to remove it first.\n", $where[0])
            if exists $entry->{depotpath};
    }

    # Manually relocate all paths
    my $map = $self->{xd}{checkout}{hash};

    my $abs_path = abs_path($path);
    if ($map->{$abs_path} and -d $abs_path) {
        move_path($path => $report);
        $target = abs_path ($report);
    }

    my $prefix = $copath[0].$SEP;
    my $length = length($copath[0]);
    foreach my $key (sort grep { index("$_$SEP", $prefix) == 0 } keys %$map) {
        $map->{$target . substr($key, $length)} = delete $map->{$key};
    }

    print loc("Checkout '%1' relocated to '%2'.\n", $path, $target);

    return;
}

sub _do_checkout {
    my ($self, $target, $report) = @_;

    if (-e $report) {
	die loc("Checkout path %1 already exists.\n", $report);
    }
    else {
	# Cwd is annoying, returning undef for paths whose parent.
	# we can't just mkdir -p $report because it might be a file,
	# so let C::Update take care about it.
	my ($anchor) = get_anchor (0, $report);
	if (length $anchor && !-e $anchor) {
	    mkpath [$anchor] or
		die loc ("Can't create checkout path %1: %2\n", $anchor, $!);
	}
    }

    my $copath = abs_path ($report);

    my ($entry, @where) = $self->{xd}{checkout}->get ($copath);
    die loc("Overlapping checkout path is not supported (%1); use 'svk checkout --detach' to remove it first.\n", $where[0])
	if exists $entry->{depotpath} && $#where > 0;

    $self->{xd}{checkout}->store_recursively ( $copath,
					       { depotpath => $target->{depotpath},
						 revision => 0,
						 '.schedule' => undef,
						 '.newprop' => undef,
						 '.deleted' => undef,
						 '.conflict' => undef,
					       });
    $self->{rev} = $target->{repos}->fs->youngest_rev unless defined $self->{rev};

    $self->SUPER::run ($target->new (report => $report,
				     copath => $copath));
    $self->_do_detach ($copath)
	if $self->{export};
    return;
}

sub _find_copath {
    my ($self, $path) = @_;
    my $abs_path = abs_path($path);
    my $map = $self->{xd}{checkout}{hash};

    # Check if this is a checkout path
    return $abs_path if defined $abs_path and $map->{$abs_path};

    # Find all copaths that matches this depotpath
    return sort grep {
        defined $map->{$_}{depotpath}
            and $map->{$_}{depotpath} eq $path
    } keys %$map;
}


1;

__DATA__

=head1 NAME

SVK::Command::Checkout - Checkout the depotpath

=head1 SYNOPSIS

 checkout DEPOTPATH [PATH]
 checkout --list
 checkout --detach [DEPOTPATH | PATH]
 checkout --relocate [DEPOTPATH | PATH] PATH

=head1 OPTIONS

 -r [--revision] arg    : act on revision ARG instead of the head revision
 -l [--list]            : list checkout paths
 -d [--detach]          : mark a path as no longer checked out
 -q [--quiet]           : quiet mode
 --export               : export mode; checkout a detached copy
 --relocate             : relocate the checkout to another path

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
