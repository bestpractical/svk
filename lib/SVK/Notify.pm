package SVK::Notify;
use SVK::I18N;
use strict;

=head1 NAME

SVK::Notify - svk entry status notification

=head1 SYNOPSIS

    $notify = SVK::Notfy->new ( report => $report, anchor => $anchor );
    $notify->node_status ('foo/bar', 'M');
    $notify->prop_status_('foo/bar', 'M');
    $notify->flush ('foo/bar');
    $notify->flush_dir ('foo');

=head1 DESCRIPTION



=cut

sub new {
    my ($class, @arg) = @_;
    my $self = bless {}, $class;
    %$self = @arg;
    return $self;
}

sub node_status : lvalue {
    my ($self, $path) = @_;
    $self->{status}{$path}[0];
}

sub prop_status : lvalue {
    my ($self, $path) = @_;
    $self->{status}{$path}[1];
}

sub flush {
    my ($self, $path, $anchor) = @_;
    my $status;
    if (($status = $self->{status}{$path}) && $status->[0] || $status->[1]) {
	print sprintf ("%1s%1s \%s\n", $status->[0] || '',
		       $status->[1] || '', $path);
    }
    elsif (!$anchor) {
	print "   ", loc("%1 - skipped\n", $path);
    }
    delete $self->{status}{$path};

}

sub flush_dir {
    my ($self, $path) = @_;
    for (grep {$path ? "$path/" eq substr ($_, 0, length($path)+1) : 1}
	 sort keys %{$self->{status}}) {
	$self->flush ($_, $path eq $_);
    }
    $self->flush ($path, 1);
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
