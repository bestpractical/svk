package SVK::SignEditor;
our @ISA = qw (SVN::Delta::Editor);
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

    $self->{sig} =_sign_gpg ($fname, join("\n", (map {"MD5 $_->[0] $_->[1]"} @{$self->{checksum}})),'');
    $self->SUPER::close_edit ($baton);
}

sub _sign_gpg {
    my ($sigfile, $plaintext) = @_;

    die "Could not write to $sigfile"
	if -e $sigfile and (-d $sigfile or not -w $sigfile);

    local *D;
    open D, "| gpg --clearsign > $sigfile.sig" or die "Could not call gpg: $!";
    print D $plaintext;
    close D;

    (-e "$sigfile.sig" and -s "$sigfile.sig") or do {
	unlink "$sigfile.sig";
	die "Cannot find $sigfile.sig, signing aborted.\n";
    };

    open D, "$sigfile.sig" or die "Cannot open $sigfile.sig: $!";
    undef $/;
    my $buf = <D>;
    unlink("$sigfile.sig");
    return $buf;
}

1;
