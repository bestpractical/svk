package SVK::Command::Cmerge;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Merge SVK::Command::Copy SVK::Command::Propset );
use SVK::XD;
use SVK::I18N;
use SVK::Editor::Combine;

sub options {
    ($_[0]->SUPER::options,
     'c|change=s',	=> 'chgspec');
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
    die loc("revision required") unless $self->{revspec} || $self->{chgspec};
    my ($fromrev, $torev);
    if ($self->{revspec}) {
	($fromrev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/
	    or die loc("revision must be N:M");
    }

    die loc("repos paths mismatch") unless $src->{repospath} eq $dst->{repospath};
    my $repos = $src->{repos};
    my $fs = $repos->fs;
    $src->{revision} ||= $fs->youngest_rev;
    $dst->{revision} ||= $fs->youngest_rev;
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

    my @chgs = split ',', $self->{chgspec};
    for (@chgs) {
	# back to normally auto merge if $fromrev is what we get from the base
	my ($fromrev, $torev);
	if (($fromrev, $torev) = m/^(\d+):(\d+)$/) {
	    --$fromrev;
	}
	elsif (($torev) = m/^(\d+)$/) {
	    $fromrev = $torev - 1;
	}
	else {
	    die loc("chgspec not recognized");
	}

	print loc("Merging with base %1 %2: applying %3 %4:%5.\n",
		  @{$base}{qw/path revision/}, $src->{path}, $fromrev, $torev);

	my $editor = SVK::Editor::Merge->new
	    ( anchor => $src->{path},
	      base_anchor => $src->{path},
	      base_root => $fs->revision_root ($fromrev),
	      target => '',
	      send_fulltext => 1,
	      cb_exist => sub { $ceditor->cb_exist (@_) },
	      cb_localmod => sub { $ceditor->cb_localmod (@_) },
	      cb_rev => sub { $fs->youngest_rev },
	      storage => $ceditor,
	);

	SVN::Repos::dir_delta ($fs->revision_root ($fromrev),
			       $src->{path}, '',
			       $fs->revision_root ($torev), $src->{path},
			       $editor, undef,
			       1, 1, 0, 1);
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
    my $ticket = SVK::Merge->find_merge_sources ($repos, $src->{path}, $newrev, 1, 1);
    $ticket->{"$uuid:$tmpbranch"} = $newrev;

    $self->do_propset_direct
	( author => $ENV{USER},
	  %$src,
	  propname => 'svk:merge',
	  propvalue => join ("\n", map {"$_:$ticket->{$_}"} sort keys %$ticket),
	  message => "cherry picking merge $self->{chgspec} to $dst->{path}",
	) unless $self->{check_only};
    my ($depot) = $self->{xd}->find_depotname ($src->{depotpath});
    ++$self->{auto};
    $self->SUPER::run (SVK::Target->new (%$src, path => $tmpbranch,
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

 -m [--message] message:    commit message
 -c [--change] chgspec:     change spec to merge
 -C [--check-only]:         don't perform actual writes
 -l [--log]:                brings the logs of merged revs to the message buffer
 --no-ticket:               don't associate the ticket tracking merge history
 -r [--revision] arg:       Needs description
 -a [--auto]:               Needs description
 --force:                   Needs description
 -s [--sign]:               Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
