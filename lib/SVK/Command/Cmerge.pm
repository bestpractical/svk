package SVK::Command::Cmerge;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Merge );
use SVK::XD;
use SVK::CombineEditor;

sub options {
    ($_[0]->SUPER::options,
     'c|change=s',	=> 'chgspec');
}

sub run {
    my ($self, $src, $dst) = @_;
    # XXX: support checkonly
    die "revision required" unless $self->{revspec} || $self->{chgspec};
    my ($fromrev, $torev);
    if ($self->{revspec}) {
	($fromrev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/
	    or die "revision must be N:M";
    }

    die "different repos?" unless $src->{repospath} eq $dst->{repospath};
    my $repos = $src->{repos};
    my ($base_path, $base_rev) = $self->find_merge_base ($repos, $src->{path}, $dst->{path});

    # find a branch target
    die "can't find a path for tmp branch" if $base_path eq '/';
    my $tmpbranch = "$src->{path}-merge-$$";

    SVK::XD::do_copy_direct ($self->{info},
			     %$src,
			     path => $base_path,
			     dpath => $tmpbranch,
			     message => "preparing for cherry picking merging",
			     rev => $base_rev,
			    ) unless $self->{check_only};

    my $fs = $repos->fs;
    my $ceditor = SVK::CombineEditor->new(tgt_anchor => $base_path, #$check_only ? $base_path : $tmpbranch,
					  base_root  => $fs->revision_root ($base_rev),
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
	    die "chgspec not recognized";
	}

	print "merging with base $base_path $base_rev applying $src->{path} $fromrev:$torev\n";

	my $fs = $repos->fs;
	my $editor = SVK::MergeEditor->new
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
				     sub { print "Committed revision $_[0].\n" })
				  ]),
		      $fs->youngest_rev);
    my $newrev = $repos->fs->youngest_rev;
    my $uuid = $repos->fs->get_uuid;

    # give ticket to src
    my $ticket = $self->find_merge_sources ($repos, $src->{path}, 1, 1);

    $ticket .= "\n$uuid:$tmpbranch:$newrev";

    SVK::XD::do_propset_direct ($self->{info},
				author => $ENV{USER},
				%$src,
				propname => 'svk:merge',
				propvalue => $ticket,
				message => "cherry picking merge $self->{chgspec} to $dst",
			       ) unless $self->{check_only};
    my ($depot) = main::find_depotname ($src->{depotpath});

    $src->{path} = $tmpbranch;
    $src->{depotpath} = "/$depot$tmpbranch";
    $self->{auto}++;
    $self->SUPER::run ($src, $dst);
    return;
}

1;
