package SVK::Command::Copy;
use strict;
our $VERSION = '0.11';
use base qw( SVK::Command::Commit );

sub options {
    ($_[0]->SUPER::options,
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return map {$self->arg_depotpath ($_)} @arg;
}

sub lock { return $_[0]->lock_none }

sub do_copy_direct {
    my ($self, %arg) = @_;
    my $fs = $arg{repos}->fs;
    my $edit = $self->get_commit_editor ($fs->revision_root ($fs->youngest_rev),
					 sub { print "Committed revision $_[0].\n" },
					 '/', %arg);
    # XXX: check parent, check isfile, check everything...
    $edit->open_root();
    $edit->copy_directory ($arg{dpath}, "file://$arg{repospath}$arg{path}",
			   $arg{rev});
    $edit->close_edit();
}

sub run {
    my ($self, $src, $dst) = @_;
    die "different repos?" if $src->{repospath} ne $dst->{repospath};
    $self->{rev} ||= $src->{repos}->fs->youngest_rev;

    $self->get_commit_message ();
    $self->do_copy_direct ( author => $ENV{USER},
			    %$src,
			    dpath => $dst->{path},
			    %$self,
			  );
    return;
}

1;

=head1 NAME

SVK::Command::Copy - Make a versioned copy

=head1 SYNOPSIS

    copy DEPOTPATH1 DEPOTPATH2

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
