package SVK::Editor::View;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw(SVK::Editor::Rename);
use SVK::I18N;

*_path_inside = *SVK::Editor::Rename::_path_inside;

sub rename_check {
    my ($self, $path) = @_;
    $path = "$self->{prefix}/$path"
	if length $self->{prefix};
    for (@{$self->{rename_map}}) {
	my ($from, $to) = @$_;
	if (_path_inside ($path, $from)) {
	    my $newpath = $path;
	    $newpath =~ s/^\Q$from\E/$to/;
	    return $newpath;
	}
    }
    return $path;
}


1;
