package SVK::Command::Move;
use strict;
our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Copy SVK::Command::Delete );
use SVK::I18N;

sub get_commit_editor {
    my $self = shift;
    # cache the editor
    $self->{commit_editor} ||= SVK::Command::Move::ProxyEdit->new(
	$self->SUPER::get_commit_editor(@_)
    );
    return $self->{commit_editor};
}

sub run {
    my ($self, $src, $dst) = @_;

    $self->SVK::Command::Copy::run($src, $dst);
    $self->get_commit_editor->set_copied(1);
    $self->SVK::Command::Delete::run($src);

    return;
}

package SVK::Command::Move::ProxyEdit;
our $AUTOLOAD;

sub new {
    my ($class, $edit) = @_;
    bless({ edit => $edit, copied => 0}, $class);
}

sub set_copied {
    my $self = shift;
    $self->{copied} = shift;
}

sub open_root {
    my $self = shift;
    # only does open_root during the "Copy" run
    $self->{edit}->open_root(@_) if !$self->{copied};
}

sub close_edit {
    my $self = shift;
    # only does close_edit during the "Delete" run
    $self->{edit}->close_edit(@_) if $self->{copied};
}

sub AUTOLOAD {
    my $self = shift;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;
    $self->{edit}->$method(@_);
}

sub DESTROY {
    my $self = shift;
    delete $self->{edit};
}

1;

__DATA__

=head1 NAME

SVK::Command::Move - Move a file or directory

=head1 SYNOPSIS

 move DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

 -m [--message] arg:     Needs description
 -C [--check-only]:      Needs description
 -s [--sign]:            Needs description
 -r [--revision] arg:    Needs description
 --force:                Needs description

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Moveright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
