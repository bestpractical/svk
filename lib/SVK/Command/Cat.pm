package SVK::Command::Cat;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;
use SVK::Util qw(slurp_fh);

sub options {
    ('r|revision=i'  => 'rev');
}

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    return @arg;
}

sub run {
    my ($self, @arg) = @_;
    for (@arg) {
	my (undef, $path, undef, undef, $repos) = main::find_repos_from_co_maybe ($_, 1);
	my $pool = SVN::Pool->new_default;
	my $fs = $repos->fs;
	my $root = $fs->revision_root ($self->{rev} || $fs->youngest_rev);
	my $stream = $root->file_contents ($path);
	# XXX: the keyword layer interface should also have reverse
	my $layer = SVK::XD::get_keyword_layer ($root, "$path");
	my $io = new IO::Handle;
	$io->fdopen(fileno(STDOUT),"w");
	$layer->via ($io) if $layer;
	slurp_fh ($stream, $io);
    }
    return;
}

1;

