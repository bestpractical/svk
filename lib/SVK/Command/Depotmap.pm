package SVK::Command::Depotmap;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw(get_buffer_from_editor get_prompt);
use YAML;
use File::Path;

sub options {
    ('l|list' => 'list',
     'i|init' => 'init');
}

sub run {
    my ($self) = @_;
    return $self->_do_list() if($self->{list});
    $self->_do_edit();
}

sub _do_list {
    my ($self) = @_;
    my $map = $self->{xd}{depotmap};
    local $\ = "\n";
    my $fmt = "%-20s %-s\n";
    printf $fmt, 'Depot', 'Path';
    print '=' x 60;
    printf $fmt, "/$_/", $map->{$_} for keys %$map;
    return;
}

sub _do_edit {
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
    for my $path (values %{$self->{xd}{depotmap}}) {
	next if -d $path;
	my $ans = get_prompt(
	    loc("Repository %1 does not exist, create? (y/n)", $path),
	    qr/^[yn]/i,
	);
	next if $ans =~ /^n/i;
        $ENV{SVNFSTYPE} ||= (($SVN::Core::VERSION =~ /^1\.0/) ? 'bdb' : 'fsfs');
	SVN::Repos::create($path, undef, undef, undef,
			   {'fs-type' => $ENV{SVNFSTYPE},
			    'bdb-txn-nosync' => '1',
			    'bdb-log-autoremove' => '1'});
    }
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Depotmap - Create or edit the depot mapping configuration

=head1 SYNOPSIS

 depotmap [OPTIONS]

=head1 OPTIONS

 -l [--list]            : list current depot mappings
 -i [--init]            : initialize a default deopt

=head1 DESCRIPTION

Run this command without any options would bring up your C<$EDITOR>,
and let you edit your depot-directory mapping.

Each line contains a map entry, the format is:

 depotname: '/path/to/repos'

The depotname may then be used as part of a DEPOTPATH:

 /depotname/path/inside/repos

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
