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
    printf($fmt,'Depot','Path');
    print '=' x 60;
    for(keys %$map) {
	printf($fmt,"/$_/",$map->{$_});
    }
    print '=' x 60;
}

sub _do_edit {
    my ($self) = @_;
    my $sep = '===edit the above depot map===';
    my $map = YAML::Dump ($self->{xd}{depotmap});
    my $new;
    if ( !$self->{'init'} ) {
        do {
            $map =
              get_buffer_from_editor( 'depot map', $sep, "$map\n$sep\n",
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
	File::Path::mkpath([$path], 0, 0711);
	SVN::Repos::create($path, undef, undef, undef,
			   {'bdb-txn-nosync' => '1',
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

    options:
    -l [--list]:    List current depot mapping
    -i [--init]:    Initialize a default deopt

=head1 DESCRIPTION

Run this command with any options would bring up your $EDITOR,
and let you edit your depot-directory mapping.

Each line contains a map entry, the format is:

 depotname: 'path/to/repos'

The depotname could be used to refer to a DEPOTPATH as

 /depotname/path/in/repos

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
