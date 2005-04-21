package SVK::Command::Import;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;

sub options {
    ($_[0]->SUPER::options,
     'f|from-checkout|force'    => 'from_checkout',
     't|to-checkout'	        => 'to_checkout',
    )
}

sub parse_arg {
    my $self = shift;
    my @arg = @_ or return;

    return if @arg > 2;
    unshift @arg, '' while @arg < 2;

    local $@;
    if (eval { $self->{xd}->find_repos($arg[1]); 1 }) {
        # Reorder to put DEPOTPATH before PATH
        @arg[0,1] = @arg[1,0];
    }
    elsif (!eval { $self->{xd}->find_repos($arg[0]); 1 }) {
        # The user entered a path
	$arg[0] = ($self->prompt_depotpath('import', undef, 1));
    }

    return ($self->arg_depotpath ($arg[0]), $self->arg_path ($arg[1]));
}

sub lock {
    my ($self, $target, $source) = @_;
    unless ($self->{xd}{checkout}->get ($source)->{depotpath}) {
	$self->{xd}->lock ($source) if $self->{to_checkout};
	return;
    }
    $source = $self->arg_copath ($source);
    die loc("Import source (%1) is a checkout path; use --from-checkout.\n", $source->{copath})
	unless $self->{from_checkout};
    die loc("Import path (%1) is different from the copath (%2)\n", $target->{path}, $source->{path})
	unless $source->{path} eq $target->{path};
    $self->lock_target ($source);
}

sub _mkpdir {
    my ($self, $target) = @_;

    $self->command (
        mkdir => { message => "Directory for svk import.", parent => 1 },
    )->run ($target);

    print loc("Import path %1 initialized.\n", $target->{depotpath});
}

sub run {
    my ($self, $target, $copath) = @_;
    lstat ($copath);
    die loc ("Path %1 does not exist.\n", $copath) unless -e $copath;
    my $root = $target->root;
    my $kind = $root->check_path ($target->{path});

    die loc("import destination cannot be a file") if $kind == $SVN::Node::file;

    if ($kind == $SVN::Node::none) {
	if ($self->{check_only}) {
	    print loc("Import path %1 will be created.\n", $target->{depotpath});
	    $target = $target->new (revision => 0, path => '/');
	}
	else {
	    $self->_mkpdir ($target);
	    $target->refresh_revision;
	    $root = $target->root;
	}
    }

    unless (exists $self->{xd}{checkout}->get ($copath)->{depotpath}) {
	$self->{xd}{checkout}->store
	    ($copath, {depotpath => '/'.$target->depotname.$target->{path},
		       '.newprop' => undef,
		       '.conflict' => undef,
		       revision => $target->{revision}});
        delete $self->{from_checkout};
    }

    $self->get_commit_message () unless $self->{check_only};
    my $committed =
	sub { my $yrev = $_[0];
	      print loc("Directory %1 imported to depotpath %2 as revision %3.\n",
			$copath, $target->{depotpath}, $yrev);

	      if ($self->{to_checkout}) {
                  $self->{xd}{checkout}->store_recursively (
                      $copath, {
                          depotpath => $target->{depotpath},
                          revision => $yrev,
                          $self->_schedule_empty,
                      }
                  );
              }
              elsif ($self->{from_checkout}) {
		  $self->committed_import ($copath)->($yrev);
	      }
	      else {
		  $self->{xd}{checkout}->store
		      ($copath, {depotpath => undef,
				 revision => undef,
				 '.schedule' => undef});
	      }
	  };
    my ($editor, %cb) = $self->get_editor ($target, $committed);

    $self->{import} = 1;
    $self->run_delta ($target->new (copath => $copath), $root, $editor, %cb);

    if ($self->{check_only}) {
	print loc("Directory %1 will be imported to depotpath %2.\n",
		  $copath, $target->{depotpath});
	$self->{xd}{checkout}->store
	    ($copath, {depotpath => undef,
		       revision => undef,
		       '.schedule' => undef});
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Import - Import directory into depot

=head1 SYNOPSIS

 import [PATH] DEPOTPATH

 # You may also list the target part first:
 import DEPOTPATH [PATH]

=head1 OPTIONS

 -m [--message] MESSAGE	: specify commit message MESSAGE
 -C [--check-only]      : try operation but make no changes
 -P [--patch] NAME	: instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -f [--from-checkout]   : import from a checkout path
 -t [--to-checkout]     : turn the source into a checkout path

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
