package SVK::Command::Log;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( HAS_SVN_MIRROR traverse_history get_encoding );
use List::Util qw(max min);
use Date::Parse qw(str2time);
use Date::Format qw(time2str);

sub options {
    ('l|limit=i'	=> 'limit',
     'r|revision=s@'	=> 'revspec',
     'x|cross'		=> 'cross',
     'v|verbose'	=> 'verbose');
}

# returns a sub for getting remote rev
sub _log_remote_rev {
    my ($repos, $path, $remoteonly, $host) = @_;
    $host ||= '';
    return sub {"r$_[0]$host"} unless HAS_SVN_MIRROR and SVN::Mirror::list_mirror ($repos);
    # save some initialization
    my $m = SVN::Mirror::is_mirrored ($repos, $path) || 'SVN::Mirror';
    sub {
	my $rrev = $m->find_remote_rev ($_[0], $repos);
	$remoteonly ? "r$rrev$host" :
	    "r$_[0]$host".($rrev ? " (orig r$rrev)" : '');
    }
}

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_co_maybe (@arg);
}

sub run {
    my ($self, $target) = @_;
    # as_depotpath, but use the base revision rather than youngest
    # for the target.

    my ($fromrev, $torev);
    # move to general revspec parser in svk::command
    if ($self->{revspec}) {
        ($fromrev, $torev) = $self->resolve_revspec($target);
	$torev ||= $fromrev;
    }
    $fromrev ||= $target->{revision};
    $torev ||= 0;
    $self->{cross} ||= 0;

    $target->as_depotpath($self->find_base_rev($target))
	if defined $target->{copath};
    my $fs = $target->{repos}->fs;

    my $print_rev = _log_remote_rev (@{$target}{qw/repos path/});

    if ($target->{revision} < max ($fromrev, $torev)) {
	print loc ("Revision too large, show log from %1.\n", $target->{revision});
	$fromrev = min ($target->{revision}, $fromrev);
	$torev = min ($target->{revision}, $torev);
    }
    my $sep = ('-' x 70)."\n";
    print $sep;
    _get_logs ($target->root, $self->{limit} || -1, $target->{path}, $fromrev, $torev,
	       $self->{verbose}, $self->{cross},
	       sub {_show_log (@_, $sep, undef, 0, $print_rev, 1, 0)} );
    return;
}

sub _get_logs {
    my ($root, $limit, $path, $fromrev, $torev, $verbose, $cross, $callback) = @_;
    my $fs = $root->fs;
    my $reverse = ($fromrev < $torev);
    my @revs;
    ($fromrev, $torev) = ($torev, $fromrev) if $reverse;
    $torev = 1 if $torev < 1;

    my $docall = sub {
	my ($rev) = @_;
	my ($root, $changed, $props);
	$root = $fs->revision_root ($rev);
	$changed = $root->paths_changed if $verbose;
	$props = $fs->revision_proplist ($rev);
	$callback->($rev, $root, $changed, $props);
    };

    traverse_history (
        root        => $root,
        path        => $path,
        cross       => $cross,
        callback    => sub {
            return 0 if !$limit--; # last

            my $rev = $_[1];
            return 1 if $rev > $fromrev; # next
            return 0 if $rev < $torev;   # last

            if ($reverse) {
                unshift @revs, $rev;
            }
            else {
                $docall->($rev);
            }
            return 1;
        },
    );

    if ($reverse) {
	my $pool = SVN::Pool->new_default;
	$docall->($_), $pool->clear for @revs;
    }
}

our $chg;
$chg->[$SVN::Fs::PathChange::modify] = 'M';
$chg->[$SVN::Fs::PathChange::add] = 'A';
$chg->[$SVN::Fs::PathChange::delete] = 'D';
$chg->[$SVN::Fs::PathChange::replace] = 'R';

sub _show_log {
    my ($rev, $root, $paths, $props, $sep, $output, $indent, $print_rev, $use_localtime, $verbatim) = @_;
    $output ||= select;
    my ($author, $date, $message) = @{$props}{qw/svn:author svn:date svn:log/};
    if (defined $use_localtime) {
	no warnings 'uninitialized';
	local $^W; # shut off uninitialized warnings in Time::Local
	$date = time2str("%Y-%m-%d %T %z", str2time ($date));
    }
    $indent = (' ' x $indent);
    $author = loc('(no author)') if !defined($author) or !length($author);
    $output->print ($indent.$print_rev->($rev).":  $author | $date\n") unless $verbatim;
    if ($paths) {
	$output->print ($indent.loc("Changed paths:\n"));
	my $enc = get_encoding;
	for (sort keys %$paths) {
	    my $entry = $paths->{$_};
	    my ($action, $propaction) = ($chg->[$entry->change_kind], ' ');
	    my ($copyfrom_rev, $copyfrom_path) = $action eq 'D' ? (-1) : $root->copied_from ($_);
	    $propaction = 'M' if $action eq 'M' && $entry->prop_mod;
	    $action = ' ' if $action eq 'M' && !$entry->text_mod;
	    $action = 'M' if $action eq 'A' && $copyfrom_path && $entry->text_mod;
	    Encode::from_to ($_, 'utf8', $enc);
	    Encode::from_to ($copyfrom_path, 'utf8', $enc) if defined $copyfrom_path;
	    $output->print ($indent.
		"  $action$propaction $_".
		    (defined $copyfrom_path ?
		     ' ' . loc("(from %1:%2)", $copyfrom_path, $copyfrom_rev) : ''
		    )."\n");
	}
    }
    $message = ($indent ? '' : "\n")."$message\n$sep";
#    $message =~ s/\n\n+/\n/mg;
    $message =~ s/^/$indent/mg if $indent and !$verbatim;
    require Encode;
    Encode::from_to ($message, 'UTF-8', get_encoding);
    $output->print ($message);
}

sub do_log {
    my (%arg) = @_;
    $arg{cross} ||= 0, $arg{limit} ||= -1;
    my $pool = SVN::Pool->new_default;
    my $fs = $arg{repos}->fs;
    my $rev = $arg{fromrev} > $arg{torev} ? $arg{fromrev} : $arg{torev};
    _get_logs ($fs->revision_root ($rev),
	       @arg{qw/limit path fromrev torev verbose cross cb_log/});
}

1;

__DATA__

=head1 NAME

SVK::Command::Log - Show log messages for revisions

=head1 SYNOPSIS

 log DEPOTPATH
 log PATH

=head1 OPTIONS

 -r [--revision] REV	: act on revision REV instead of the head revision
 -l [--limit] REV	: stop after displaying REV revisions
 -x [--cross]           : track revisions copied from elsewhere
 -v [--verbose]         : print extra information

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
