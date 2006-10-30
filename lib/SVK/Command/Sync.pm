package SVK::Command::Sync;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::I18N;

sub options {
    ('s|skipto=s'	=> 'skip_to',
     'a|all'		=> 'sync_all',
     't|torev=s'	=> 'torev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return (@arg ? @arg : undef) if $self->{sync_all};

    return map {$self->arg_uri_maybe ($_)} @arg;
}

sub run {
    my ( $self, @arg ) = @_;

    my @mirrors;
    die loc("argument skipto not allowed when multiple target specified")
        if $self->{skip_to} && ( $self->{sync_all} || $#arg > 0 );

    if ( $self->{sync_all} ) {
        my %explicit = defined $arg[0] ? ( map { $_ => 1 } @arg ) : ();
        @arg = sort keys %{ $self->{xd}{depotmap} }
            unless defined $arg[0];
        for my $orig_arg (@arg) {
            my ( $arg, $path ) = $orig_arg =~ m{^/?([^/]*)/?(.*)?$};
            my ($depot) = eval { $self->{xd}->find_depot($arg) };
            unless ( defined $depot ) {
                print loc( "%1 does not contain a valid depotname\n",
                    $orig_arg );
                next;
            }

            my @tempnewarg = grep { SVK::Path->_to_pclass( "/$path", 'Unix' )->subsumes($_) }
                $depot->mirror->entries;

            if ( $path && $explicit{$orig_arg} && !@tempnewarg ) {
                print loc( "no mirrors found underneath %1\n", $orig_arg );
                next;
            }
            push @mirrors, map { $depot->mirror->get($_) } @tempnewarg;
        }
    } else {
        @mirrors = map { $_->mirror->get( $_->path ) } @arg;
    }

    for my $m (@mirrors) {
	my $run_sync = sub {
	    $m->sync_snapshot($self->{skip_to}) if $self->{skip_to};
	    $m->run( $self->{torev} );
	    1;
	};
        if ( $self->{sync_all} ) {
            print loc( "Starting to synchronize %1\n", $m->get_svkpath->depotpath );
            eval { $run_sync->() };
            if ($@) {
                warn $@;
                last if ( $@ =~ /^Interrupted\.$/m );
            }
            next;
        }
        else {
	    $run_sync->();
        }
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Sync - Synchronize a mirrored depotpath

=head1 SYNOPSIS

 sync DEPOTPATH
 sync --all [DEPOTNAME|DEPOTPATH...]

=head1 OPTIONS

 -a [--all]             : synchronize all mirrored paths under
                          the DEPOTNAME/DEPOTPATH(s) provided
 -s [--skipto] REV      : start synchronization at revision REV
 -t [--torev] REV       : stop synchronization at revision REV

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
