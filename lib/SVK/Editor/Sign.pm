package SVK::Editor::Sign;
our @ISA = qw (SVN::Delta::Editor);
use SVK::I18N;
use File::Temp;

sub add_file {
    my ($self, $path, @arg) = @_;
    my $baton = $self->SUPER::add_file ($path, @arg);
    $self->{filename}{$baton} = $path;
    return $baton;
}

sub open_file {
    my ($self, $path, @arg) = @_;
    my $baton = $self->SUPER::open_file ($path, @arg);
    $self->{filename}{$baton} = $path;
    return $baton;
}

sub close_file {
    my $self = shift;
    my ($baton, $checksum, $pool) = @_;
    push @{$self->{checksum}}, [$checksum, $self->{filename}{$baton}];
    $self->SUPER::close_file (@_);
}

sub close_edit {
    my ($self, $baton) = @_;
    my ($fh, $fname) =  mkstemps ("/tmp/svk-sigXXXXX", '.tmp');

    $self->{sig} =_sign_gpg
	($fname, join("\n", "ANCHOR: $self->{anchor}",
		      (map {"MD5 $_->[0] $_->[1]"} @{$self->{checksum}})),'');
    $self->SUPER::close_edit ($baton);
}

sub _sign_gpg {
    my ($sigfile, $plaintext) = @_;

    die loc("could not write to %1", $sigfile)
	if -e $sigfile and (-d $sigfile or not -w $sigfile);

    local *D;
    open D, "| gpg --clearsign > $sigfile.sig" or die loc("could not call gpg: %1", $!);
    print D $plaintext;
    close D;

    (-e "$sigfile.sig" and -s "$sigfile.sig") or do {
	unlink "$sigfile.sig";
	die loc("cannot find %1, signing aborted", "$sigfile.sig");
    };

    open D, "$sigfile.sig" or die loc("cannot open %1: %2", "$sigfile.sig", $!);
    undef $/;
    my $buf = <D>;
    unlink("$sigfile.sig");
    return $buf;
}

1;
