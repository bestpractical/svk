package SVK::Notify;
use SVK::I18N;
use SVK::Util qw( abs2rel $SEP to_native get_encoding);
use strict;

=head1 NAME

SVK::Notify - svk entry status notification

=head1 SYNOPSIS

    $notify = SVK::Notify->new;
    $notify->node_status ('foo/bar', 'M');
    $notify->prop_status ('foo/bar', 'M');
    $notify->flush ('foo/bar');
    $notify->flush_dir ('foo');

=head1 DESCRIPTION



=cut

sub flush_print {
    my ($path, $status, $extra) = @_;
    no warnings 'uninitialized';
    $extra = " - $extra" if $extra;
    print sprintf ("%1s%1s%1s \%s\%s\n", @{$status}[0..2],
		   length $path ? $path : '.', $extra);
}

sub skip_print {
    my ($path) = @_;
    print "    ", loc("%1 - skipped\n", $path);
}

sub print_report {
    my ($print, $is_copath, $report, $target) = @_;
    my $enc = Encode::find_encoding (get_encoding);
    # XXX: $report should already be in native encoding, so this is wrong
    my $print_native = $enc->name eq 'utf8'
	? $print
	: sub { to_native ($_[0]);
		goto \&$print;
	    };
    return $print_native unless defined $report;
    sub {
	my $path = shift;
	if ($target) {
	    if ($target eq $path) {
		$path = '';
	    }
	    else {
		$path = abs2rel($path, $target => undef, $is_copath ? () : '/');
	    }
	}
	if (length $path) {
	    $print_native->($is_copath ? SVK::Target->copath ($report, $path)
			               : length $report ? "$report/$path" : $path, @_);
	}
	else {
	    my $r = length $report ? $report : '.';
	    $print_native->($is_copath ? SVK::Target->copath('', $r) : $r,
			    @_);
	}
    };
}

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, $class;
    %$self = @arg;
    return $self;
}

sub new_with_report {
    my ($class, $report, $target, $is_copath) = @_;
    $report =~ s/\Q$SEP\E$//o if $report; # strip trailing slash
    $class->new	( cb_skip => print_report (\&skip_print, $is_copath, $report),
		  cb_flush => print_report (\&flush_print, $is_copath, $report, $target));
}

sub node_status {
    my ($self, $path, $s) = @_;
    $self->{status}{$path}[0] = $s if defined $s;
    return $self->{status}{$path}[0];
}

my %prop = ( 'U' => 0, 'g' => 1, 'G' => 2, 'M' => 3, 'C' => 4);

sub prop_status {
    my ($self, $path, $s) = @_;
    my $st = $self->{status}{$path};
    $st->[1] = $s if defined $s
	# node status allow prop
	&& !($st->[0] && ($st->[0] eq 'A' || $st->[0] eq 'R'))
	    # not overriding things more informative
	    && (!$st->[1] || $prop{$s} > $prop{$st->[1]});
    return $self->{status}{$path}[1];
}

sub hist_status {
    my ($self, $path, $s) = @_;
    $self->{status}{$path}[2] = $s if defined $s;
    return $self->{status}{$path}[2];
}

sub flush {
    my ($self, $path, $anchor) = @_;
    return if $self->{quiet};
    my $status = $self->{status}{$path};
    if ($status && grep {$_} @{$status}[0..2]) {
	$self->{cb_flush}->($path, $status) if $self->{cb_flush};
    }
    elsif (!$status && !$anchor) {
	$self->{cb_skip}->($path) if $self->{cb_skip};
    }
    delete $self->{status}{$path};
}

sub flush_dir {
    my ($self, $path) = @_;
    return if $self->{quiet};
    for (grep {$path ? index($_, "$path/") == 0 : $_}
	 sort keys %{$self->{status}}) {
	$self->flush ($_, $path eq $_);
    }
    $self->flush ($path, 1);
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
