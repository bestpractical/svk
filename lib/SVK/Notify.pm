package SVK::Notify;
use SVK::I18N;
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
    print sprintf ("%1s%1s%1s \%s\%s\n", @{$status}[0..2], $path, $extra);
}

sub skip_print {
    my ($path) = @_;
    print "    ", loc("%1 - skipped\n", $path);
}

sub print_report {
    my ($print, $report, $target) = @_;
    return $print unless defined $report;
    sub {
	my $path = shift;
	if ($target) {
	    if ($target eq $path) {
		$path = '';
	    }
	    else {
		$path =~ s|^\Q$target/||;
	    }
	}
	$print->($path ? "$report$path" : $report || '.', @_);
    };
}

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, $class;
    %$self = @arg;
    return $self;
}

sub new_with_report {
    my ($class, $report, $target) = @_;
    $class->new	( cb_skip => print_report (\&skip_print, $report),
		  cb_flush => print_report (\&flush_print, $report, $target));
}

sub node_status {
    my ($self, $path, $s) = @_;
    $self->{status}{$path}[0] = $s if defined $s;
    return $self->{status}{$path}[0];
}

sub prop_status {
    my ($self, $path, $s) = @_;
    $self->{status}{$path}[1] = $s if defined $s
	&& exists $self->{status}{$path}[0] && $self->{status}{$path}[0] ne 'A';
    return $self->{status}{$path}[1];
}

sub hist_status {
    my ($self, $path, $s) = @_;
    $self->{status}{$path}[2] = $s if defined $s;
    return $self->{status}{$path}[2];
}

sub flush {
    my ($self, $path, $anchor) = @_;
    my $status;
    if (($status = $self->{status}{$path}) && grep {$_} @{$status}[0..2]) {
	$self->{cb_flush}->($path, $status) if $self->{cb_flush};
    }
    elsif (!$status && !$anchor) {
	$self->{cb_skip}->($path) if $self->{cb_skip};
    }
    delete $self->{status}{$path};
}

sub flush_dir {
    my ($self, $path) = @_;
    for (grep {$path ? "$path/" eq substr ($_, 0, length($path)+1) : $_ ne $path}
	 sort keys %{$self->{status}}) {
	$self->flush ($_, $path eq $_);
    }
    $self->flush ($path, 1) unless $path;
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
