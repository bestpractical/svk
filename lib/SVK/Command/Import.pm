package SVK::Command::Import;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    $arg[1] = '' if $#arg < 1;

    return ($self->arg_depotpath ($arg[0]), $self->arg_path ($arg[1]));
}

sub lock {
    my ($self, $target, $source) = @_;
    return $self->lock_none
	unless $self->{xd}{checkout}->get ($source)->{depotpath};
    $source = $self->arg_copath ($source);
    ($self->{force} && $target->{path} eq $source->{path}) ?
	$self->lock_target ($source) : $self->lock_none;
}

sub run {
    my ($self, $target, $source) = @_;

    $self->get_commit_message () unless $self->{check_only};

    $self->{xd}->do_import ( %$self,
			     %$target,
			     copath => $source,
			   );
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Import - Import directory into depot

=head1 SYNOPSIS

    import DEPOTPATH [PATH]

=head1 OPTIONS

    -m [--message] message:        commit message
    -C [--check-only]: don't perform actual writes
    -s [--sign]:	Needs description
    --force:	Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
