package SVK::Command::List;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use constant opt_recursive => 0;
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( to_native get_encoder reformat_svn_date );

sub options {
    ('r|revision=s'  => 'rev',
     'v|verbose'	   => 'verbose',
     'f|full-path'      => 'fullpath',
     'd|depth=i'      => 'depth');
}

sub parse_arg {
    my ($self, @arg) = @_;
    @arg = ('') if $#arg < 0;
    return map {$self->arg_co_maybe ($_)} @arg;
}

sub run {
    my ($self, @arg) = @_;
    my $exception = '';

    my $enc = get_encoder;
    while ( my $arg = shift @arg ) {
        $arg = $arg->as_depotpath;
        eval {
            $self->run_command_recursively(
                $self->apply_revision($arg),
                sub {
                    my ( $target, $kind, $level ) = @_;
                    if ( $level == -1 ) {
                        return if $kind == $SVN::Node::dir;
                        die loc( "Path %1 is not versioned.\n",
                            $target->path_anchor )
                            unless $kind == $SVN::Node::file;
                    }
                    $self->_print_item( $target, $kind, $level, $enc );
                }
            );
            print "\n" if @arg;
        };
        $exception .= "$@" if $@;
    }

    die($exception) if($exception);
}

sub _print_item {
    my ( $self, $target, $kind, $level, $enc ) = @_;
    my $root = $target->root;
    if ( $self->{verbose} ) {
        my $rev = $root->node_created_rev( $target->path );
        my $fs  = $target->repos->fs;

        my $svn_date = $fs->revision_prop( $rev, 'svn:date' );

        # The author name may be undef
        no warnings 'uninitialized';

        # Additional fields for verbose: revision author size datetime
        printf "%7ld %-8.8s %10s %12s ", $rev,
            $fs->revision_prop( $rev, 'svn:author' ),
            ($kind == $SVN::Node::dir) ? "" : $root->file_length( $target->path ),
            reformat_svn_date( "%b %d %H:%M", $svn_date );
    }

    my $output_path;
    if ( $self->{'fullpath'} ) {
        $output_path = $target->report;
    }
    else {
        print " " x ($level);
        $output_path = Path::Class::File->new_foreign( 'Unix', $target->path )
            ->basename;
    }
    to_native( $output_path, 'path', $enc );
    print $output_path;
    print( ( $kind == $SVN::Node::dir ? '/' : '' ) . "\n" );

}

1;

__DATA__

=head1 NAME

SVK::Command::List - List entries in a directory from depot

=head1 SYNOPSIS

 list [DEPOTPATH | PATH...]

=head1 OPTIONS

 -r [--revision] REV    : act on revision REV instead of the head revision
 -R [--recursive]       : descend recursively
 -d [--depth] LEVEL     : recurse at most LEVEL levels deep; use with -R
 -f [--full-path]       : show pathname for each entry, instead of a tree
 -v [--verbose]         : print extra information

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
