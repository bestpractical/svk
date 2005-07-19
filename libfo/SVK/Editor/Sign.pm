package SVK::Editor::Sign;

require SVN::Delta;
our @ISA = qw (SVN::Delta::Editor);
use SVK::I18N;
use autouse 'SVK::Util' => qw (tmpfile);

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
    $self->{sig} =_sign_gpg
	(join("\n", "ANCHOR: $self->{anchor}",
	      (map {"MD5 $_->[0] $_->[1]"} @{$self->{checksum}})),'');
    $self->SUPER::close_edit ($baton);
}

sub _sign_gpg {
    my ($plaintext) = @_;
    my $sigfile = tmpfile("sig-", OPEN => 0);
    local *D;
    my $pgp = $ENV{SVKPGP} || 'gpg';
    open D, "| $pgp --clearsign > $sigfile" or die loc("could not call gpg: %1", $!);
    print D $plaintext;
    close D;

    (-e "$sigfile" and -s "$sigfile") or do {
	unlink "$sigfile";
	die loc("cannot find %1, signing aborted", $sigfile);
    };

    open D, "$sigfile" or die loc("cannot open %1: %2", $sigfile, $!);
    undef $/;
    my $buf = <D>;
    unlink($sigfile);
    return $buf;
}

1;
