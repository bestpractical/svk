package SVK::Path::Checkout;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'SVK::Path';

__PACKAGE__->mk_accessors(qw(xd report));

use autouse 'SVK::Util' => qw( get_anchor catfile abs2rel get_encoder to_native );

=head1 NAME

SVK::Path::Checkout - SVK path class associating a checkout

=head1 SYNOPSIS

 See below

=head1 DESCRIPTION

The class represents a node in svk depot, associated with a checkout
copy.

=cut

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    unless (ref $self->report) {
	$self->report($self->_to_pclass($self->report))
	    if defined $self->report && length $self->report;
    }
    return $self;
}

sub root {
    my $self = shift;
    return $self->view->root
	if $self->view;
    unless ($self->xd) {
	$self->xd(shift);
	Carp::cluck unless $self->xd;
    }
    Carp::cluck,die unless defined $self->{copath};
    $self->xd->xdroot(%$self);
}

=head2 copath

Return the checkout path of the target, optionally with additional
path component.

=cut

my $_copath_catsplit = $^O eq 'MSWin32' ? \&catfile :
sub { defined $_[0] && length $_[0] ? "$_[0]/$_[1]" : "$_[1]" };

sub copath {
    my $self = shift;
    my $copath = ref($self) ? $self->{copath} : shift;
    my $paths = shift;
    return $copath unless defined $paths && length $paths;
    return $_copath_catsplit->($copath, $paths);
}

sub report { __PACKAGE__->make_accessor('report')->(@_) }

sub report_copath {
    my ($self, $copath) = @_;
    my $report = length($self->{report}) ? $self->{report} : undef;
    abs2rel( $copath, $self->{copath} => $report );
}

sub copath_targets {
    my $self = shift;
    return $self->copath unless exists $self->{targets}[0];
    my $enc = get_encoder;
    return map { $self->copath($_) }
        map {my $t = $_; to_native($t, 'path', $enc); $t }
            @{$self->{targets}};
}

sub contains_copath {
    my ($self, $copath) = @_;
    foreach my $base ($self->copath_targets) {
	if ($copath ne abs2rel( $copath, $base) ) {
	    return 1;
	}
    }
    return 0;
}

sub descend {
    my ($self, $entry) = @_;
    $self->SUPER::descend($entry);
    to_native($entry, 'path');
    $self->{copath} = catfile($self->{copath}, $entry);

    $self->report( catfile($self->report, $entry) );
    return $self;
}

sub anchorify {
    my ($self) = @_;
    $self->SUPER::anchorify;
    ($self->{copath}, $self->{copath_target}) = get_anchor(1, $self->{copath});

    if (defined $self->report) {
	$self->report($self->_to_pclass($self->report))
	    unless ref($self->report);
	$self->report($self->report->parent);
    }

}

sub _get_inspector {
    my $self = shift;
    return SVK::Inspector::XD->new
	({ xd => $self->xd,
	   path => $self->new,
	   _pool => $self->pool,
	   xdroot => $self->root(pool => $self->pool),
	 });
}

=head2 get_editor

Returns the L<SVK::Editor::XD> object, L<SVK::Inspector::XD>, and the callback 
hash used by L<SVK::Editor::Merge>

=cut

sub get_editor {
    my ($self, %arg) = @_;
    my ($copath, $path, $spath) = ($self->{copath}, $self->{path}, $arg{store_path});
    $spath = $path unless defined $spath;
    my $encoding = $self->xd->{checkout}->get($copath)->{encoding};
    $path = '' if $path eq '/';
    $spath = '' if $spath eq '/';
    $encoding = Encode::find_encoding($encoding) if $encoding;
    $arg{get_path} = sub { $_[0] = "$path/$_[0]" };
    $arg{get_store_path} = sub { $_[0] = "$spath/$_[0]" };
    my $storage = SVK::Editor::XD->new (%arg,
					get_copath =>
            sub { to_native ($_[0], 'path', $encoding) if $encoding;
                  $_[0] = $self->copath($_[0]) },
					repos => $self->{repos},
					target => $self->{targets}[0] || '',
					xd => $self->xd);
    my $inspector = $self->inspector;

    return ($storage, $inspector,
        cb_rev => sub {
            my ($path) = @_;
            my $copath;
            ($path,$copath) = $inspector->get_paths($path);
            return $self->xd->{checkout}->get($copath)->{revision};
        },

        cb_conflict => sub {
            my ($path) = @_;
            my $copath;
            ($path, $copath) = $inspector->get_paths($path);
            $self->xd->{checkout}->store ($copath, {'.conflict' => 1})
                unless $arg{check_only};
        },
        cb_prop_merged => sub { 
            return if $arg{check_only};
            my ($path, $name) = @_;
            my $copath;
            ($path, $copath) = $inspector->get_paths($path);
            my $entry = $self->xd->{checkout}->get ($copath);
            warn $entry unless ref $entry eq 'HASH';
            my $prop = $entry->{'.newprop'};
            delete $prop->{$name};
            $self->xd->{checkout}->store ($copath, {'.newprop' => $prop,
                         keys %$prop ? () :
                         ('.schedule' => undef)}
                        );
        });

}

=head1 SEE ALSO

L<SVK::Path>

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
