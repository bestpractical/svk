package SVK::Command::Verify;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;

sub options {
    ();
}

sub parse_arg {
    my ($self, @arg) = @_;
    $self->usage if $#arg < 0;
    return ($arg[0], $self->arg_depotname ($arg[1] || '//'));
}

sub lock { $_[0]->lock_none }

sub _verify {
    my ($repos, $sig, $chg) = @_;
    my $fs = $repos->fs;
    my $editor = SVK::VerifyEditor->new ( sig => $sig,
					  repos => $repos );

    # should really just use paths_changed
    SVN::Repos::dir_delta ($fs->revision_root ($chg-1), '/', '',
			   $fs->revision_root ($chg), '/',
			   $editor, undef,
			   0, 1, 0, 1
			  );

    print "Verification failed\n" if $editor->{fail};


}

sub run {
    my ($self, $chg, $depot) = @_;
    my $target = $self->arg_depotpath ("/$depot/");
    my $fs = $target->{repos}->fs;
    my $sig = $fs->revision_prop ($chg, 'svk:signature');
    return "No signature found for change $chg at /$depot/\n" unless $sig;
    _verify ($target->{repos}, $sig, $chg);
}

# XXX: Don't need this editor once root->paths_changed is available.
package SVK::VerifyEditor;
use SVK::Util qw(resolve_svm_source);
our @ISA = ('SVN::Delta::Editor');

sub add_file {
    my ($self, $path, @arg) = @_;
    return $path;
}

sub open_file {
    my ($self, $path, @arg) = @_;
    return $path;
}

sub close_file {
    my ($self, $path, $checksum, $pool) = @_;
    $self->{checksum}{"/$path"} =  $checksum;
}

sub close_edit {
    my ($self, $baton) = @_;
    my $sig = $self->{sig};
    local *D;
    # verify the signature
    open D, "|gpg --verify --batch --no-tty";
    print D $sig;
    close D;

    if ($?) {
	print "Can't verify signature\n";
	$self->{fail} = 1;
	return;
    }
    # verify the content
    my ($anchor) = $sig =~ m/^ANCHOR: (.*)$/m;
    my ($path) = resolve_svm_source ($self->{repos}, split (':', $anchor));
    while ($sig =~ m/^MD5\s(.*?)\s(.*?)$/gm) {
	my ($md5, $filename) = ($1, $2);
	my $checksum = delete $self->{checksum}{"$path/$filename"};
	if ($checksum ne $md5) {
	    print "checksum for $path/$filename mismatched: $checksum vs $md5\n";
	    $self->{fail} = 1;
	    return;
	}
    }
    # unsigned change
    if (my @unsig = keys %{$self->{checksum}}) {
	print "Checksum for changed path ".join (',', @unsig)." not signed.\n";
	$self->{fail} = 1;
    }
}

1;

__DATA__

=head1 NAME

SVK::Command::Verify - Verify change signatures

=head1 SYNOPSIS

 verify CHANGE [DEPOTNAME]

=head1 OPTIONS

 None

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
