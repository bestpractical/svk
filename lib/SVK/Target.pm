package SVK::Target;
use strict;
our $VERSION = $SVK::VERSION;
use SVK::XD;
use SVK::Util qw( get_anchor );


=head1 NAME

SVK::Target - SVK targets

=head1 SYNOPSIS


=head1 DESCRIPTION

=cut

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, $class;
    %$self = @arg;
    return $self;
}

sub root {
    my ($self, $xd) = @_;
    if ($self->{copath}) {
	$xd->xdroot (%$self);
    }
    else {
	SVK::XD::Root->new ($self->{repos}->fs->revision_root
			    ($self->{revision}));
    }
}

sub same_repos {
    my ($self, @other) = @_;
    for (@other) {
	return 0 if $self->{repos} ne $_->{repos};
    }
    return 1;
}

sub anchorify {
    my ($self) = @_;
    die "anchorify $self->{depotpath} already with targets"
	if $self->{targets};
    ($self->{path}, $self->{targets}[0], $self->{depotpath}, undef, $self->{report}) =
	get_anchor (1, $self->{path}, $self->{depotpath}, $self->{report});
    ($self->{copath}) = get_anchor (0, $self->{copath}) if $self->{copath};
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
