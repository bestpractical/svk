package SVK::Command::Depotmap;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;
use SVK::Util qw(get_buffer_from_editor);
use YAML;
use File::Path;

sub run {
    my ($self) = @_;
    my $sep = '===edit the above depot map===';
    my $map = YAML::Dump ($self->{info}->{depotmap});
    my $new;
    do {
	$map = get_buffer_from_editor ('depot map', $sep, "$map\n$sep\n",
				       '/tmp/svk-depotmapXXXXX');
	$new = eval { YAML::Load ($map) };
	print "$@\n" if $@;
    } while ($@);
    print "New depot map saved.\n";
    $self->{info}->{depotmap} = $new;
    for my $path(values %{$self->{info}->{depotmap}}) {
	my $ans;
	next if -d $path;
	print "Repository $path does not exist, create? (y/n) ";
	while (<STDIN>) {
	    $ans = $1 if $_ =~ m/^([yn])/i;
	    last if $ans;
	}
	next if $ans eq 'n';
	File::Path::mkpath([$path], 0, 0711);
	SVN::Repos::create($path, undef, undef, undef,
			   {'bdb-txn-nosync' => '1',
			    'bdb-log-autoremove' => '1'});
    }
    return;
}

1;

=head1 NAME

depotmap - Create or edit the depot mapping configuration.

=head1 SYNOPSIS

    depotmap

=head1 DESCRIPTION

Each line contains a map entry, the format is:

 depotname: 'path/to/repos'

The depotname could be used in DEPOTPATH as

 /depotname/path/in/repos

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
