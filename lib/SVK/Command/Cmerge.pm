package SVK::Command::Cmerge;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Merge SVK::Command::Copy SVK::Command::Propset );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Combine;

sub options {
    ($_[0]->SUPER::options);
}

sub parse_arg {
    my $self = shift;
    $self->SVK::Command::Merge::parse_arg (@_);
}

sub lock {
    my $self = shift;
    $self->SVK::Command::Merge::lock (@_);
}

sub run {
    my ($self, $src, $dst) = @_;
    # XXX: support checkonly
    my @revlist = $self->parse_revlist;

    my $repos = $src->{repos};
    my $fs = $repos->fs;
    my $base = SVK::Merge->auto (%$self, repos => $repos, src => $src, dst => $dst,
				 ticket => 1)->{base};
    # find a branch target
    die loc("cannot find a path for temporary branch")
	if $base->{path} eq '/';
    my $tmpbranch = "$src->{path}-merge-$$";

    $self->do_copy_direct
	( %$src,
	  path => $base->{path},
	  dpath => $tmpbranch,
	  message => "preparing for cherry picking merging",
	  rev => $base->{revision},
	) unless $self->{check_only};

    my $ceditor = SVK::Editor::Combine->new(tgt_anchor => $base->{path},
					    #$check_only ? $base_path : $tmpbranch,
					    base_root => $base->root,
					    pool => SVN::Pool->new,
					   );

    for (@revlist) {
	my ($fromrev, $torev) = @$_;
	print loc("Merging with base %1 %2: applying %3 %4:%5.\n",
		  @{$base}{qw/path revision/}, $src->{path}, $fromrev, $torev);

	SVK::Merge->new (%$self, repos => $repos,
			 base => $src->new (revision => $fromrev),
			 src => $src->new (revision => $torev), dst => $dst,
			)->run ($ceditor, $ceditor->callbacks,
				# XXX: should be base_root's rev?
				cb_rev => sub { $fs->youngest_rev });
    }

    $ceditor->replay (SVN::Delta::Editor->new
		      (_debug => 0,
		       _editor => [ $repos->get_commit_editor
				    ("file://$src->{repospath}",
				     $tmpbranch,
				     $ENV{USER}, "merge $self->{chgspec} from $src->{path}",
				     sub { print loc("Committed revision %1.\n", $_[0]) })
				  ]),
		      $fs->youngest_rev);
    my $newrev = $fs->youngest_rev;
    my $uuid = $fs->get_uuid;

    # give ticket to src
    my $ticket = SVK::Merge->new (xd => $self->{xd})->
	find_merge_sources ($src->new (revision => $newrev), 1, 1);
    $ticket->{"$uuid:$tmpbranch"} = $newrev;

    unless ($self->{check_only}) {
	my $oldmessage = $self->{message};
	$self->{message} = "cherry picking merge $self->{chgspec} to $dst->{path}";
	$self->do_propset_direct ($src, 'svk:merge',
				  join ("\n", map {"$_:$ticket->{$_}"} sort keys %$ticket));
	$self->{message} = $oldmessage;
    }

    my ($depot) = $self->{xd}->find_depotname ($src->{depotpath});
    ++$self->{auto};
    $self->SUPER::run ($src->new (path => $tmpbranch,
				  depotpath => "/$depot$tmpbranch",
				  revision => $fs->youngest_rev),
		       $dst);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Cmerge - Merge specific changes

=head1 SYNOPSIS

 cmerge -c CHGSPEC DEPOTPATH [PATH]
 cmerge -c CHGSPEC DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

 -m [--message] arg     : specify commit message ARG
 -c [--change] arg      : act on comma-separated revisions ARG
 -C [--check-only]      : try operation but make no changes
 -l [--log]             : use logs of merged revisions as commit message
 -r [--revision] N:M    : act on revisions between N and M
 -a [--auto]            : merge from the previous merge point
 -S [--sign]            : sign this change
 --no-ticket            : do not record this merge point

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
