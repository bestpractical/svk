package SVK::Command::Update;
use strict;
our $VERSION = '0.11';

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ('r|revision=i'  => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_copath ($_)} @arg;
}

sub lock {
    my ($self, @arg) = @_;
    $self->lock_target ($_) for @arg;
}

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
	$self->{rev} = $target->{repos}->fs->youngest_rev
	    unless defined $self->{rev};

	$self->{xd}->do_update
	    ( %$target,
	      rev => $self->{rev},
	    );
    }
    return;
}

1;

=head1 NAME

update - Bring changes from the repository into checkout copies.

=head1 SYNOPSIS

    update [PATH...]

=head1 OPTIONS

    -r [--revision]:      revision

=head1 DESCRIPTION

Synchronize checkout copies to revision given by -r or to HEAD
revision by deafult.

For each updated item a line will start with a character reporting the
action taken. These characters have the following meaning:

  A  Added
  D  Deleted
  U  Updated
  C  Conflict
  G  Merged
  g  Merged without actual change

A character in the first column signifies an update to the actual
file, while updates to the file's props are shown in the second
column.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
