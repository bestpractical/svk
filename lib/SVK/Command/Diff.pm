package SVK::Command::Diff;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;
use SVK::DiffEditor;

sub options {
    ("v|verbose"	=> 'verbose',
     "r|revision=s" => 'revspec');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;

    return map {$self->arg_co_maybe ($_)} @arg;
}

sub run {
    my ($self, $target, $target2) = @_;
    my $fs = $target->{repos}->fs;

    if (($self->{revspec} && (my ($fromrev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/))
	|| $target2) {
	if ($target->{copath}) {
	    die "Invalid arguments" if $target2;
	}
	elsif ($target2) {
	    die "different repository"
		if $target->{repospath} ne $target2->{repospath};
	}

	$target2 ||= { path => $target->{path} };
	$fromrev ||= $self->{revspec} || $fs->youngest_rev;
	$torev ||= $self->{revspec} || $fs->youngest_rev;
	my $baseroot = $fs->revision_root ($fromrev);
	my $newroot = $fs->revision_root ($torev);

	if ($baseroot->check_path ($target->{path}) == $SVN::Node::file) {
	    SVK::DiffEditor::output_diff (\*STDOUT, $target->{path}, "revision $fromrev",
					  "revision $torev",
					  $target->{path}, $target2->{path},
					  $baseroot->file_contents ($target->{path}),
					  $newroot->file_contents ($target2->{path}));
	    return;
	}

	my $editor = SVK::DiffEditor->new
	    ( cb_basecontent => sub { my ($rpath) = @_;
				      my $base = $baseroot->file_contents ("$target->{path}/$rpath");
				      return $base;
				  },
	      cb_baseprop => sub { my ($rpath, $pname) = @_;
				   return $baseroot->node_prop ("$target->{path}/$rpath", $pname);
			       },
	      llabel => "revision $fromrev",
	      rlabel => "revision $torev",
	      lpath  => $target->{path},
	      rpath  => $target2->{path},
	    );

	SVN::Repos::dir_delta ($baseroot, $target->{path}, '',
			       $newroot, $target2->{path},
			       $editor, undef,
			       1, 1, 0, 1);

    }
    else {
	die "revision should be N:M or N"
	    if $self->{revspec} && $self->{revspec} !~ /^\d+$/;

	my ($txn, $xdroot) = SVK::XD::create_xd_root ($self->{info}, %$target);
	my $baseroot = $self->{revspec} ? $fs->revision_root ($self->{revspec}) : $xdroot;

	if ($baseroot->check_path ($target->{path}) == $SVN::Node::file) {
	    SVK::DiffEditor::output_diff (\*STDOUT, $target->{path},
					  'revision '.
					  ($self->{revspec} || $self->{info}->{checkout}->get
					   ($target->{copath})->{revision}),
					  "local",
					  $target->{path}, $target->{path},
					  $baseroot->file_contents ($target->{path}),
					  SVK::XD::get_fh ($xdroot, '<',
							   $target->{path}, $target->{copath}));
	    return;
	}

	my $editor = SVK::DiffEditor->new
	    ( cb_basecontent =>
	      sub { my ($rpath) = @_;
		    $baseroot->file_contents ("$target->{path}/$rpath");
		},
	      cb_baseprop =>
	      sub { my ($rpath, $pname) = @_;
		    return $baseroot->node_prop ("$target->{path}/$rpath", $pname);
	      },
	      cb_llabel =>
	      sub { my ($rpath) = @_;
		    $self->{revspec} ||
		    'revision '.
			$self->{info}->{checkout}->get ("$target->{copath}/$rpath")->{revision};
	      },
	      rlabel => "local",
	    );

	SVK::XD::checkout_delta ($self->{info},
				 %$target,
				 baseroot => $baseroot,
				 xdroot => $xdroot,
				 strict_add => 1,
				 editor => $editor,
				);
	$txn->abort if $txn;
    }
    return;
}

1;
