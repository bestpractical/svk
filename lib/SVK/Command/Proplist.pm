package SVK::Command::Proplist;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 0;
use SVK::XD;
use SVK::I18N;

sub options {
    ('v|verbose' => 'verbose',
     'r|revision=i' => 'rev',
     'revprop' => 'revprop',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;

    @arg = ('') if $#arg < 0;
    return map { $self->_arg_revprop ($_) } @arg;
}

sub run {
    my ($self, @arg) = @_;
    die loc ("Revision required.\n")
	if $self->{revprop} && !defined $self->{rev};

    for my $target (@arg) {
        if ($self->{revprop}) {
            $self->_show_props
		( $target,
		  $target->repos->fs->revision_proplist($self->{rev}),
		  $self->{rev}
		);
            next;
        }

	$target = $target->as_depotpath ($self->{rev}) if defined $self->{rev};
        $self->_show_props( $target, $target->root->node_proplist($target->path) );
    }

    return;
}

sub _show_props {
    my ($self, $target, $props, $rev) = @_;

    %$props or return;

    if ($self->{revprop}) {
        print loc("Unversioned properties on revision %1:\n", $rev);
    }
    else {
        print loc("Properties on %1:\n", length $target->report ? $target->report : '.');
    }

    for my $key (sort keys %$props) {
        my $value = $props->{$key};
        print $self->{verbose} ? "  $key: $value\n" : "  $key\n";
    }
}

sub _arg_revprop {
    my $self = $_[0];
    goto &{$self->can($self->{revprop} ? 'arg_depotroot' : 'arg_co_maybe')};
}

sub _proplist {
    my ($self, $target) = @_;

    return $target->repos->fs->revision_proplist($self->{rev})
	if $self->{revprop};

    if (defined $self->{rev}) {
        $target = $target->as_depotpath ($self->{rev});
    }
    return $target->root->node_proplist($target->path);
}


1;

__DATA__

=head1 NAME

SVK::Command::Proplist - List all properties on files or dirs

=head1 SYNOPSIS

 proplist PATH...

=head1 OPTIONS

 -R [--recursive]       : descend recursively
 -v [--verbose]         : print extra information
 -r [--revision] REV    : act on revision REV instead of the head revision
 --revprop              : operate on a revision property (use with -r)

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
