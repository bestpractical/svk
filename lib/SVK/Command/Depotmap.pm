package SVK::Command::Depotmap;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( get_buffer_from_editor abs_path move_path );
use YAML;
use File::Path;

sub options {
    ('l|list' => 'list',
     'i|init' => 'init',
     'd|delete|detach' => 'detach',
     'relocate' => 'relocate');
}

sub parse_arg {
    my ($self, @arg) = @_;

    ++$self->{hold_giant};
    $self->rebless ('depotmap::add')->{add} = 1 if @arg >= 2 and !$self->{relocate};

    return undef
	unless $self->{add} or $self->{detach} or $self->{relocate};

        @arg or die loc("Need to specify a depot name");

        my $depot = shift(@arg);
        @arg or die loc("Need to specify a path name") unless $self->{detach};

        my $map = $self->{xd}{depotmap};
        my $path = $depot;
        my $abs_path = abs_path($path);
        $depot =~ s{/}{}go;

        return ($depot, @arg) if $self->{add} or $map->{$depot} or !$abs_path;

        # Translate repospath into depotname
        foreach my $name (sort keys %$map) {
            (abs_path($map->{$name}) eq $abs_path) or next;
            move_path($path => $arg[0]) if $self->{relocate} and -d $path;
            return ($name, @arg);
        }

        return ($depot, @arg);
}

sub run {
    my ($self) = @_;
    my $sep = '===edit the above depot map===';
    my $map = YAML::Dump ($self->{xd}{depotmap});
    my $new;
    if ( !$self->{'init'} ) {
        do {
            $map =
              get_buffer_from_editor( loc('depot map'), $sep, "$map\n$sep\n",
                'depotmap' );
            $new = eval { YAML::Load($map) };
            print "$@\n" if $@;
        } while ($@);
        print loc("New depot map saved.\n");
        $self->{xd}{depotmap} = $new;
    }
    $self->{xd}->create_depots;
    return;
}

package SVK::Command::Depotmap::add;
use base qw(SVK::Command::Depotmap);
use SVK::I18N;

sub run {
    my ($self, $depot, $path) = @_;

    die loc("Depot '%1' already exists; use 'svk depotmap --detach' to remove it first.\n", $depot)
        if $self->{xd}{depotmap}{$depot};

    $self->{xd}{depotmap}{$depot} = $path;

    print loc("New depot map saved.\n");
    $self->{xd}->create_depots;
}

package SVK::Command::Depotmap::relocate;
use base qw(SVK::Command::Depotmap);
use SVK::I18N;

sub run {
    my ($self, $depot, $path) = @_;

    die loc("Depot '%1' does not exist in the depot map.\n", $depot)
        if !$self->{xd}{depotmap}{$depot};

    $self->{xd}{depotmap}{$depot} = $path;

    print loc("Depot '%1' relocated to '%2'.\n", $depot, $path);
    $self->{xd}->create_depots;
}

package SVK::Command::Depotmap::detach;
use base qw(SVK::Command::Depotmap);
use SVK::I18N;

sub run {
    my ($self, $depot) = @_;
    delete $self->{xd}{depotmap}{$depot}
        or die loc("Depot '%1' does not exist in the depot map.\n", $depot);

    print loc("Depot '%1' detached.\n", $depot);
    return;
}

package SVK::Command::Depotmap::list;
use base qw(SVK::Command::Depotmap);
use SVK::I18N;

sub parse_arg { undef }

sub run {
    my ($self) = @_;
    my $map = $self->{xd}{depotmap};
    my $fmt = "%-20s\t%-s\n";
    printf $fmt, loc('Depot'), loc('Path');
    print '=' x 60, "\n";
    printf $fmt, "/$_/", $map->{$_} for sort keys %$map;
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Depotmap - Create or edit the depot mapping configuration

=head1 SYNOPSIS

 depotmap [OPTIONS]
 depotmap DEPOTNAME /path/to/repository

 depotmap --list
 depotmap --detach [DEPOTNAME | PATH]
 depotmap --relocate [DEPOTNAME | PATH] PATH

=head1 OPTIONS

 -i [--init]            : initialize a default depot
 -l [--list]            : list current depot mappings
 -d [--detach]          : remove a depot from the mapping
 --relocate             : relocate the depot to another path

=head1 DESCRIPTION

Run this command without any options would bring up your C<$EDITOR>,
and let you edit your depot-directory mapping.

Each line contains a map entry, the format is:

 depotname: '/path/to/repos'

The depotname may then be used as part of a DEPOTPATH:

 /depotname/path/inside/repos

Depot creation respects $ENV{SVNFSTYPE}, which is default to fsfs for
svn 1.1 or later, and bdb for svn 1.0.x.

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
