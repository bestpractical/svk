package SVK::Command::Propget;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::Util qw(get_buffer_from_editor);

sub options {
    ('strict'	=> 'strict',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 1;
    return ($arg[0], map {$self->arg_co_maybe ($_)} @arg[1..$#arg]);
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, $pname, @targets) = @_;

    foreach my $target (@targets) {
        print $target->path, ' - ' if @targets > 1 and !$self->{strict};
        print $self->{xd}->do_proplist ($target)->{$pname};
        print "\n" if !$self->{strict};
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Propget - Display a property on path

=head1 SYNOPSIS

 propget PROPNAME [PATH|DEPOTPATH...]

=head1 OPTIONS

 --strict:                  Do not print an extra newline at the end of the
                            property values; when there are multiple paths
                            involved, do not prefix path names before values.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
