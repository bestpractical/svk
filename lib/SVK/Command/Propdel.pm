package SVK::Command::Propdel;
use strict;
our $VERSION = '0.13';
use base qw( SVK::Command::Propset );
use SVK::XD;
use SVK::I18N;

sub parse_arg {
    my ($self, @arg) = @_;
    $self->usage if $#arg < 1;
    return ($arg[0], map {$self->arg_co_maybe ($_)} @arg[1..$#arg]);
}

sub lock {
    my $self = shift;
    $_->{copath} ? $self->lock_target ($_) : $self->lock_none
	for (@_[1..$#_]);
}

sub do_propdel {
    my ($self, $pname, $target) = @_;

    if ($target->{copath}) {
	die "Propdel on checkout path not supported yet";
	$self->{xd}->do_propset
	    ( %$target,
	      propname => $pname,
	      propvalue => undef,
	    );
    }
    else {
	$self->get_commit_message ();
	$self->do_propset_direct ( author => $ENV{USER},
				   %$target,
				   propname => $pname,
				   propvalue => undef,
				   message => $self->{message},
				 );
    }
}

sub run {
    my ($self, $pname, @targets) = @_;
    $self->do_propdel ($pname, $_) for @targets;
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Propdel - Delete a property on files or dirs

=head1 SYNOPSIS

    propdel PROPNAME PATH...

=head1 OPTIONS

    NONE

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
