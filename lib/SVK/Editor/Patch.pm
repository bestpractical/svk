package SVK::Editor::Patch;
use strict;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVN::Delta::Editor);

=head1 NAME

SVK::Editor::Patch - An editor to serialize editor calls.

=head1 SYNOPSIS

    $patch = SVK::Editor::Patch->new...
    # feed things to $patch
    $patch->drive ($editor);

=head1 DESCRIPTION

C<SVK::Editor::Patch> serializes incoming editor calls in a tree
structure. C<$editor->{edit_tree}> is an array indexed by the baton id
of directories. The value of each entry is an array of editor calls
that have baton id as parent directory. Each entry of editor calls is
an array with the first element being the child baton id (if any), and
then the method name and its arguments.

=cut

sub baton_at {
    my ($self, $func) = @_;
    return -1
	if $func eq 'set_target_revision' || $func eq 'open_root' || $func eq 'close_edit';
    return $func =~ m/^(?:add|open|absent)/ ? 1 : 0;
}

our $AUTOLOAD;

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;
    my $baton;

    pop @arg if ref ($arg[-1]) eq '_p_apr_pool_t';

    if ((my $baton_at = $self->baton_at ($func)) >= 0) {
	$baton = $arg[$baton_at];
    }
    else {
	$baton = 0;
    }

    my $ret = $func =~ m/^(?:add|open)/ ? ++$self->{batons} : undef;
    push @{$self->{edit_tree}[$baton]}, [$ret, $func, @arg];
    return $ret;
}

sub apply_textdelta {
    my ($self, $baton, @arg) = @_;
    pop @arg if ref ($arg[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;
    push @{$self->{edit_tree}[$baton]}, [undef, 'apply_textdelta', $baton, @arg, undef];
    open my ($svndiff), '>', \$self->{edit_tree}[$baton][-1][-1];
    return [SVN::TxDelta::to_svndiff ($svndiff)];
}

sub drive {
    my ($self, $editor, $calls, $baton) = @_;
    $calls ||= $self->{edit_tree}[0];
    # XXX: Editor::Merge calls $pool->default, which is unhappy with svn::pool objects.
    my $pool = SVN::Pool::create (undef);
    for (@$calls) {
	my ($next, $func, @arg) = @$_;
	next unless $func;
	my ($ret, $baton_at);
	$arg[$baton_at] = $baton
	    if ($baton_at = $self->baton_at ($func)) >= 0;

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

	$self->drive ($editor, $self->{edit_tree}[$next], $ret)
	    if $next;
    }
    SVN::Pool::apr_pool_destroy ($pool);
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
