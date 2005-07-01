package SVK::Command::Switch;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Update );
use SVK::XD;
use SVK::I18N;
use File::Spec;

sub options {
    ($_[0]->SUPER::options,
     'd|delete|detach' => 'detach',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;

    if ($self->{detach}) {
        goto &{ $self->rebless ('checkout::detach')->can ('parse_arg') };
    }

    return if $#arg < 0 || $#arg > 1;
    my $depotpath = $self->arg_depotpath ($arg[0]);
    return ($depotpath, $self->arg_copath ($arg[1] || ''));
}

sub lock { $_[0]->lock_target ($_[2]) }

sub run {
    my ($self, $target, $cotarget) = @_;
    die loc("different depot") unless $target->same_repos ($cotarget);

    my ($entry, @where) = $self->{xd}{checkout}->get ($cotarget->{copath});
    die loc("Can only switch checkout root.\n")
	unless $where[0] eq $cotarget->{copath};

    $self->{update_target_path} = $target->{path};
#    switch to related_to once the api is ready
    # check if the switch has a base at all
    die loc("path %1 does not exist.\n", $target->{report})
	if $target->root->check_path ($target->{path}) == $SVN::Node::none;
    SVK::Merge->auto (%$self, repos => $target->{repos},
		      src => $cotarget, dst => $target);
#    die loc ("%1 is not related to %2.\n", $cotarget->{report}, $target->{report})
#	unless $cotarget->new->as_depotpath->related_to ($target);

    $self->SUPER::run ($cotarget);

    $self->{xd}{checkout}->store ($cotarget->{copath},
				  {depotpath => $target->{depotpath},
				   revision => $target->{revision}});
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Switch - Switch to another branch and keep local changes

=head1 SYNOPSIS

 switch DEPOTPATH [PATH]

=head1 OPTIONS

 -r [--revision] REV	: act on revision REV instead of the head revision
 -d [--detach]          : mark a path as no longer checked out

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
