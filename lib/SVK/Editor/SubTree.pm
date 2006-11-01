package SVK::Editor::SubTree;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use Class::Autouse qw( SVK::Editor::Patch );

require SVN::Delta;
use base 'SVK::Editor';

__PACKAGE__->mk_accessors(qw(master_editor anchor anchor_baton changes needs_touch));

=head1 NAME

SVK::Editor::Translate - An editor that translates path names

=head1 SYNOPSIS

 my $editor = ...
 # stack the translate editor on
 $editor = SVK::Editor::Translated-> (_editor => [$editor], translate => sub {$_[0]})

=cut

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = our $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;

    if ($func =~ m/^(?:add|open|delete)/) {
	if ($arg[0] eq $self->anchor) {
	    ++$self->{needs_touch} if $func eq 'add_directory';
	    return $self->anchor_baton;
	}
	return $self->anchor_baton unless $arg[0] =~ s{^\Q$self->{anchor}/}{};
    }
    elsif ($func =~ m/^close_(?:file|directory)/) {
	return if $arg[0] eq $self->anchor_baton;
	return unless defined $arg[0];
    }

    ++$self->{changes} unless $func eq 'set_target_revision';
    $self->master_editor->$func(@arg);
}


1;
