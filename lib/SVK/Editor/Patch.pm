package SVK::Editor::Patch;
use strict;
our $VERSION = '0.15';
our @ISA = qw(SVN::Delta::Editor);

=head1 NAME

SVK::Editor::Patch - An editor to serialize editor calls.

=head1 SYNOPSIS

    $patch = SVK::Editor::Patch->new...
    # feed things to $patch
    $patch->drive ($editor);

=cut

our $AUTOLOAD;

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = $AUTOLOAD;
    my $class = ref ($self);
    $func =~ s/^${class}::(SUPER::)?//;

    pop @arg if ref ($arg[-1]) eq '_p_apr_pool_t';
    push @{$self->{calls}}, [$func, @arg];
    return ++$self->{batons} if $func =~ m/^(?:add|open)/;
}

sub apply_textdelta {
    my ($self, $baton, @arg) = @_;
    pop @arg if ref ($arg[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;
    push @{$self->{calls}}, ['apply_textdelta', $baton, @arg, undef];
    open my ($svndiff), '>', \$self->{calls}[-1][-1];
    return [SVN::TxDelta::to_svndiff ($svndiff)];
}

sub drive {
    my ($self, $editor) = @_;
    $self->{batons} = 0;
    my $pool = SVN::Pool->new;
    # XXX: Improve pool usage here
    for (@{$self->{calls}}) {
	my ($func, @arg) = @$_;
	if ($func eq 'set_target_revision' || $func eq 'open_root') {
	}
	elsif ($func =~ m/^(?:add|open|absent)/) {
	    $arg[1] = $self->{batonholder}{$arg[1]};
	}
	else {
	    my $arg = $arg[0];
	    $arg[0] = $self->{batonholder}{$arg} unless $func eq 'close_edit';
	    delete $self->{batonholder}{$arg}
		if $func =~ m/^close_(?:file|dir)/;
	}
	my $ret;
	if ($func eq 'apply_textdelta') {
	    my $svndiff = pop @arg;
	    $ret = $editor->apply_textdelta (@arg, $pool);
	    if ($ret && $#$ret > 0) {
		my $stream = SVN::TxDelta::parse_svndiff (@$ret, 1, $pool);
		print $stream $svndiff;
	    }
	}
	else {
	    $ret = $editor->$func (@arg, $pool);
	}

	if ($func =~ m/^(?:add|open)/) {
	    $self->{batonholder}{++$self->{batons}} = $ret;
	}
    }
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
